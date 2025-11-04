[![Actions Status](https://github.com/tbrowder/RakuAdventWP-Poster/actions/workflows/linux.yml/badge.svg)](https://github.com/tbrowder/RakuAdventWP-Poster/actions) [![Actions Status](https://github.com/tbrowder/RakuAdventWP-Poster/actions/workflows/macos.yml/badge.svg)](https://github.com/tbrowder/RakuAdventWP-Poster/actions) [![Actions Status](https://github.com/tbrowder/RakuAdventWP-Poster/actions/workflows/windows.yml/badge.svg)](https://github.com/tbrowder/RakuAdventWP-Poster/actions)

TITLE
=====

RakuAdventWP::Poster

SUBTITLE
========

Convert Rakudoc (Pod6) to Gutenberg-friendly HTML and upload to WordPress.

Synopsis
========

    # Convert Pod6 to HTML
    raku-advent-convert article.rakudoc --out article.html

    # Upload as draft using config + env vars
    raku-advent-upload --title "Day N: Great Raku Post" --content-file article.html \
      --status draft

    # One-shot convert + upload
    raku-advent-post --in article.rakudoc --title "Day N: Great Raku Post" \
      --status draft

Features
========

  * Clean HTML from .rakudoc (Pod6) for Gutenberg

  * WordPress REST API upload with Application Passwords

  * Category/Tag by name (auto-create optional) or by ID

  * Featured image upload (+ alt text)

  * Author by id/name/login/email

  * Scheduling via local `--date` or UTC `--date-gmt`

  * XDG config + env var overrides, CLI wins

  * One-shot CLI: `raku-advent-post`

Install
=======

    zef install .   # from this directory

Configuration
=============

Default path: `~/.config/raku-advent/config.json`

    :lang<json>
    {
      "site": "https://raku-advent.blog",
      "user": "you@example.com",
      "app-pass": "abcd abcd abcd abcd",
      "default-cats": "Raku Advent 2025",
      "default-tags": "Raku, Advent"
    }

Environment variables
---------------------

    export RAKU_ADVENT_SITE="https://raku-advent.blog"
    export RAKU_ADVENT_USER="you@example.com"
    export RAKU_ADVENT_APP_PASS="abcd abcd abcd abcd"
    export RAKU_ADVENT_CATS="Raku Advent 2025"
    export RAKU_ADVENT_TAGS="Raku, Advent"

Credential checklist (raku-advent.blog)
=======================================

1. You have a WordPress user on the site.

2. Your role is Author or higher.

3. In your WP profile, create an Application Password (copy it once).

4. Prefer env var `RAKU_ADVENT_APP_PASS` to avoid secrets in the file.

5. Revoke the app password any time in your profile.

Usage
=====

Convert
-------

    raku-advent-convert input.rakudoc --out article.html

Upload (common)
---------------

    raku-advent-upload --title "Day 12: Fancy Raku" --content-file article.html \
      --status draft

With featured image
-------------------

    raku-advent-upload --title "Post with Image" --content-file article.html \
      --featured ./images/hero.png --featured-alt "Camel in snow"

Resolve author and schedule (UTC recommended)
---------------------------------------------

    raku-advent-upload --title "Scheduled Post" --content-file article.html \
      --status future --date-gmt "2025-12-12 13:30" \
      --author-name "Raku Advent Editor"

One-shot: convert + upload
--------------------------

    raku-advent-post --in article.rakudoc --title "Day 9: How Raku Shines" \
      --status draft

If you omit taxonomy flags, defaults from `~/.config/raku-advent/config.json` are applied (`default-cats`, `default-tags`).

Notes
=====

  * If both `--date-gmt` and `--date` are provided, `--date-gmt` wins.

  * Without author flags, WordPress uses the credentialed user.

  * If tax names don’t exist and `--create-tax yes` (default), they are created.

Development
===========

  * Testing: `zef test .`

  * Code style: 4-space indent, no cuddled else/elsif, boolean words `and`/<or>.

  * PRs welcome.

License
=======

Artistic-2.0

