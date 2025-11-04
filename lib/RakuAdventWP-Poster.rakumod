unit module RakuAdventWP-Poster;

use MONKEY-SEE-NO-EVAL;

use HTTP::UserAgent;
use JSON::Fast;
use MIME::Base64;
use Pod::To::HTML;

# ============================================================
# Config loader
# Priority: CLI overrides > ENV > JSON file (~/.config/raku-advent/config.json)
# ============================================================

sub config-path() is export {
    my $xdg = %*ENV< XDG_CONFIG_HOME > // ( $*HOME ?? $*HOME ~ '/.config' !! '' );
    return $xdg.IO.add('raku-advent/config.json').Str;
}

sub load-config(*%overrides --> Hash) is export {
    #my %cfg = {};
    my %cfg := {};

    my $path = config-path();
    if $path.IO.f {
        my $raw = try slurp $path;
        %cfg = from-json($raw) if $raw.defined and $raw.chars;
    }

    # ENV
    %cfg<site>         //= %*ENV< RAKU_ADVENT_SITE > if %*ENV< RAKU_ADVENT_SITE >:exists;
    %cfg<user>         //= %*ENV< RAKU_ADVENT_USER > if %*ENV< RAKU_ADVENT_USER >:exists;
    %cfg<app-pass>     //= %*ENV< RAKU_ADVENT_APP_PASS > if %*ENV< RAKU_ADVENT_APP_PASS >:exists;
    %cfg<default-cats> //= %*ENV< RAKU_ADVENT_CATS > if %*ENV< RAKU_ADVENT_CATS >:exists;
    %cfg<default-tags> //= %*ENV< RAKU_ADVENT_TAGS > if %*ENV< RAKU_ADVENT_TAGS >:exists;

    # Overrides
    for %overrides.kv -> $k, $v {
        %cfg{$k} = $v if $v.defined;
    }

    return %cfg;
}

# ============================================================
# Converter
# ============================================================

sub convert-rakudoc-to-html(Str:D $rakudoc --> Str) is export {
    my $as-pod = "=begin pod\n$rakudoc\n=end pod\n";
    EVAL $as-pod;                      # populates $=pod
    my $html = Pod::To::HTML.render($=pod);

    # Strip full-page wrappers if present.
    $html ~~ s:g/ '<!DOCTYPE html>' .*? '<body>' //;
    $html ~~ s:g/ '</body>' \s* '</html>' //;

    return $html;
}

# ============================================================
# WordPress REST client
# ============================================================

class WP::Client {
    has Str $.site is required;
    has Str $.user is required;
    has Str $.app-pass is required;

    has $.api-root;
    has HTTP::UserAgent $.ua;
    has %.hdr;

    submethod TWEAK() {
        #$!api-root = $!site.subst(/'\/'+ % '/', '').chomp('/') ~ '/wp-json/wp/v2';
        $!api-root = ($!site.trim
                         .subst(/<!after ':'> '/' ** 2..*/, '/', :g)
                         .subst(/'/'+ $/, ''))
                      ~ '/wp-json/wp/v2';

        my $cred   = MIME::Base64.encode("{$!user}:{$!app-pass}", :str);
        %!hdr      = 'Authorization' => "Basic $cred";
        $!ua       = HTTP::UserAgent.new(:throw-exceptions(False));
    }

    method !url(Str:D $endpoint, *%q --> Str) {
        my $u = "{$!api-root}/{$endpoint}";
        if %q and %q.elems {
            my $qs = %q.keys.sort.map({ "{$_}={%q{$_}.encode('percent')}" }).join('&');
            $u ~= "?$qs";
        }
        $u
    }

    method get(Str:D $endpoint, *%q --> HTTP::Response) {
        $!ua.get(self!url($endpoint, |%q), :headers(%!hdr));
    }

    method post(Str:D $endpoint, %json --> HTTP::Response) {
        $!ua.post(self!url($endpoint), :content(to-json(%json)), :headers(%!hdr, 'Content-Type' => 'application/json'));
    }

    method post-binary(Str:D $endpoint, Blob:D $bytes, *%headers --> HTTP::Response) {
        my %h = %!hdr;
        %h{$_} = %headers{$_} for %headers.keys;
        $!ua.post(self!url($endpoint), :content($bytes), :headers(%h));
    }

    method ensure(HTTP::Response:D $res, Str:D $what) {
        unless $res.is-success {
            die "{$what} failed (HTTP {$res.code}): {$res.status-line}\n" ~ ($res.content // '');
        }
    }

    # ----- Taxonomies -----
    method parse-csv-names(Str:D $csv --> Seq) { $csv.split(',').map(*.trim).grep(*.chars) }
    method parse-csv-ids(Str:D $csv --> Seq)   { $csv.split(/\s*','\s*/).map(*.Int).grep(* > 0) }

    method find-term(Str:D $taxonomy, Str:D $name --> Hash) {
        my $r = self.get($taxonomy, :per_page(100), :search($name));
        self.ensure($r, "Lookup $taxonomy '$name'");
        my @items = try from-json($r.content) // [];
        my $lc = $name.lc;
        my %hit = @items.first({ .<name> and .<name>.lc eq $lc }) // Hash.new;
        %hit
    }

    method ensure-terms(Str:D $taxonomy, @names, :$create = True --> Array[Int]) {
        my @ids = gather for @names -> $n {
            next unless $n.defined and $n.chars;
            my %t = self.find-term($taxonomy, $n);
            if %t<id> { take %t<id>.Int; next; }
            if $create {
                my $r = self.post($taxonomy, { name => $n });
                self.ensure($r, "Create $taxonomy '$n'");
                my %b = try from-json($r.content) // {};
                take %b<id>.Int if %b<id>;
            }
        }
        @ids.unique.Array
    }

    # ----- Media -----
    method guess-mime(Str:D $path --> Str) {
        given $path.lc {
            when *.ends-with('.jpg')  or *.ends-with('.jpeg') { 'image/jpeg' }
            when *.ends-with('.png')                          { 'image/png'  }
            when *.ends-with('.gif')                          { 'image/gif'  }
            when *.ends-with('.webp')                         { 'image/webp' }
            when *.ends-with('.svg')                          { 'image/svg+xml' }
            default                                           { 'application/octet-stream' }
        }
    }

    method upload-media(Str:D $path, Str :$alt = '' --> Int) {
        my $bytes = try slurp($path, :bin) // die "Cannot read image: $path";
        my $fn = $path.IO.basename;
        my %hdr = (
            'Content-Type'        => self.guess-mime($fn),
            'Content-Disposition' => qq:to/H/.chomp;
                attachment; filename="{ $fn.encode('percent') }"
                H
        );
        my $r = self.post-binary('media', $bytes, |%hdr);
        self.ensure($r, "Upload media '$fn'");
        my %b = try from-json($r.content) // {};
        my $id = %b<id> // 0;
        if $id > 0 and $alt.chars {
            my $r2 = self.post("media/$id", { alt_text => $alt });
            self.ensure($r2, "Set alt text for media $id");
        }
        $id
    }

    # ----- Author -----
    method find-user(:$display-name, :$login, :$email --> Int) {
        if $email and $email.chars {
            my $r = self.get('users', :per_page(100), :search($email), :context('edit'));
            self.ensure($r, "Lookup user by email");
            my @i = try from-json($r.content) // [];
            my %hit = @i.first({ .<email> and .<email>.lc eq $email.lc }) // Nil;
            return %hit<id>.Int if %hit and %hit<id>;
        }
        if $login and $login.chars {
            my $r = self.get('users', :per_page(100), :search($login), :context('edit'));
            self.ensure($r, "Lookup user by login");
            my @i = try from-json($r.content) // [];
            my $lc = $login.lc;
            my %hit = @i.first({ (.{'slug'} and .{'slug'}.lc eq $lc) or (.{'name'} and .{'name'}.lc eq $lc) }) // Nil;
            return %hit<id>.Int if %hit and %hit<id>;
        }
        if $display-name and $display-name.chars {
            my $r = self.get('users', :per_page(100), :search($display-name), :context('edit'));
            self.ensure($r, "Lookup user by display name");
            my @i = try from-json($r.content) // [];
            my $lc = $display-name.lc;
            my %hit = @i.first({ (.{'name'} and .{'name'}.lc eq $lc) or (.{'slug'} and .{'slug'}.lc eq $lc) }) // Nil;
            return %hit<id>.Int if %hit and %hit<id>;
        }
        0
    }

    # ----- Posts -----
    method normalize-dt(Str $s --> Str) {
        my $t = $s.trim;
        return $t if $t.index('T').defined;        # looks ISO-like
        my $u = $t.subst(' ', 'T');
        $u ~~ / \:\d\d\:\d\d / ?? $u !! ($u ~ ':00')
    }

    method create-post(%opt --> Hash) {
        my %payload = (
            title      => %opt<title>,
            content    => %opt<content>,
            status     => %opt<status> // 'draft',
            sticky     => %opt<sticky> // False,
        );

        %payload<slug>           = %opt<slug> if %opt<slug>:exists and %opt<slug>;
        %payload<excerpt>        = %opt<excerpt> if %opt<excerpt>:exists and %opt<excerpt>;
        %payload<categories>     = %opt<categories> // [];
        %payload<tags>           = %opt<tags> // [];
        %payload<featured_media> = %opt<featured-media> if %opt<featured-media>:exists and %opt<featured-media>;
        %payload<author>         = %opt<author-id> if %opt<author-id>:exists and %opt<author-id>;

        if %opt<date-gmt>:exists and %opt<date-gmt> {
            %payload<date_gmt> = self.normalize-dt(%opt<date-gmt>);
        }
        elsif %opt<date>:exists and %opt<date> {
            %payload<date> = self.normalize-dt(%opt<date>);
        }

        my $r = self.post('posts', %payload);
        self.ensure($r, 'Create post');
        try from-json($r.content) // {}
    }
}

# ============================================================
# Public high-level helper
# ============================================================

sub upload(
    :$site!, :$user!, :$app-pass!,
    :$title!, :$content!,
    :$status = 'draft',
    :$slug, :$excerpt, :$sticky = False,
    :$cat-names, :$tag-names, :$cats, :$tags,
    :$create-tax = True,
    :$featured, :$featured-alt = '',
    :$author-id, :$author-name, :$author-login, :$author-email,
    :$date, :$date-gmt
    --> Hash
) is export {
    my $wp = WP::Client.new(:$site, :$user, :$app-pass);

    # Resolve taxonomies
    my @categories = $cats ?? $wp.parse-csv-ids($cats).Array !! [];
    my @tags       = $tags ?? $wp.parse-csv-ids($tags).Array !! [];

    if $cat-names {
        @categories = (@categories, $wp.ensure-terms('categories', $wp.parse-csv-names($cat-names), :create($create-tax))).unique.Array;
    }
    if $tag-names {
        @tags = (@tags, $wp.ensure-terms('tags', $wp.parse-csv-names($tag-names), :create($create-tax))).unique.Array;
    }

    # Featured media
    my $featured-id = 0;
    if $featured and $featured.chars {
        $featured-id = $wp.upload-media($featured, :alt($featured-alt));
    }

    # Author
    my $resolved-author = 0;
    if $author-id { $resolved-author = $author-id.Int; }
    elsif $author-name or $author-login or $author-email {
        $resolved-author = $wp.find-user(:display-name($author-name // ''), :login($author-login // ''), :email($author-email // ''));
    }

    # Build and create
    return $wp.create-post({
        title           => $title,
        content         => $content,
        status          => $status,
        slug            => $slug // '',
        excerpt         => $excerpt // '',
        sticky          => $sticky ?? True !! False,
        categories      => @categories,
        tags            => @tags,
        'featured-media'=> $featured-id,
        'author-id'     => $resolved-author,
        date            => $date // '',
        'date-gmt'      => $date-gmt // '',
    });
}
