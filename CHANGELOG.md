# Changelog

All notable changes to this project are documented in this file. Each version heading
links to its [GitHub release](https://github.com/dropstream/omniauth-shopline/releases),
where the notes are generated from the merged pull requests.

## [0.1.0] - 2026-08-27

First release published to RubyGems.org. Everything below is relative to the state of
`master` before it, which is how the gem was installed until now (`git:` in a Gemfile).

### Changed

- Runtime dependencies are declared as `omniauth >= 2.0, < 4` and
  `omniauth-oauth2 >= 1.8, < 3`. A plugin's ceiling becomes a ceiling in every
  application that installs it, so this allows the next major of both gems rather than
  blocking consumers on the day one ships. The floors are where OmniAuth 2 support
  actually begins — `omniauth-oauth2` 1.8.0 is its first release to require
  `omniauth ~> 2.0` — and CI runs the suite against those floors as well as against the
  newest resolvable versions.
- Requires Ruby >= 3.2, tested on 3.2 through 4.0.
- The app key and secret are read from the `client_id`/`client_secret` positional
  arguments, with `app_key`/`app_secret` accepted as named options. Previously the
  strategy read `options.app_key`, which the positional arguments never set, so every
  request went out with an empty `appKey`.
- `client_options[:site]` is only derived from `handle` when it still holds the
  `{handle}` placeholder, so an explicitly configured site now survives.
- Removed the unused `token_params` default (`grant_type: authorization_code`). The
  token endpoint takes only `{"code": ...}`, so the option never reached SHOPLINE.
- Development toolchain: Bundler 4.x, `rake ~> 13.0`, `rspec ~> 3.13`, `webmock ~> 3.25`.
- Added GitHub Actions for CI, a weekly `bundle-audit` run, and releases published to
  RubyGems.org from the GitHub Releases UI via trusted publishing (OIDC, no stored API
  key).

### Added

- `LICENSE.txt` (MIT) is declared in the gemspec, along with `required_ruby_version` and
  the usual `homepage`/`changelog`/`rubygems_mfa_required` metadata.
- CSRF protection for the callback. SHOPLINE has no `state` parameter, so the nonce
  travels in `customField` — the documented pass-through — and is verified against the
  session. Disable with `verify_state: false`.
- Verification of the `sign` SHOPLINE appends to the callback query, computed the way
  [SHOPLINE's own SDK](https://github.com/shoplineos/shopline-sdk-go/blob/main/client/sign.go)
  computes it. Disable with `verify_signature: false`.
- `scope` in the credentials hash, which the README documented but the code did not
  provide.
- `handle` is exposed as a reader on the strategy.
- Integration specs covering the request phase, the token exchange and its signature,
  state and signature verification, the auth hash, and the `callback_url` overrides.

### Fixed

- The authorize URL put its query string in front of the `#` fragment
  (`/admin/oauth-web/?appKey=...#/oauth/authorize`), because `OAuth2::Client#authorize_url`
  cannot build a URL for a hash-routed page. SHOPLINE's admin page never read those
  params. It is now built by hand as
  `/admin/oauth-web/#/oauth/authorize?appKey=...`.
- The token request was signed with the sorted-parameter scheme SHOPLINE uses for GETs
  (`appkey=..&timestamp=..`). A POST is signed over the request body concatenated with
  the millisecond timestamp, and the signed string is now the exact body that is sent.
- Every callback failed with `csrf_detected`: the request phase never wrote
  `omniauth.state`, and SHOPLINE does not echo a `state` parameter, so
  `OmniAuth::Strategies::OAuth2#callback_phase` rejected the callback before the token
  exchange.
- `callback_url` no longer doubles a mount prefix. The override added `script_name` to
  `callback_path`, but OmniAuth 2 moved `script_name` into `callback_path` itself, so a
  strategy mounted under a prefix (for example Devise's `/users`) would have sent
  `redirectUri=http://host/users/users/auth/shopline/callback`.
- A token response without an access token used to `fail!` from inside
  `build_access_token` and hand the resulting Rack triple back as the access token. It
  now raises `OAuth2::Error`, which OmniAuth turns into an `invalid_credentials` failure.
- The callback nonce and signature are compared in constant time.
- The token's `scope` reaches `OAuth2::AccessToken` under a string key. It was passed
  with a symbol key, which `access_token.params['scope']` never found, so
  `extra['scope']` was always `nil`.
- Development scripts in `bin/` and the spec suite are no longer packaged into the gem.

[0.1.0]: https://github.com/dropstream/omniauth-shopline/releases/tag/v0.1.0
