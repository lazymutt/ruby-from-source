# build_ruby

Build a current Ruby from source on macOS, no Homebrew required.

I prefer Python, but I've always been interested in Ruby. macOS doesn't ship a current Ruby (or Python), so you either compile it yourself or use Homebrew, and I've never been a fan of Homebrew. This script does the compiling for you.

## What it does

It downloads, builds, and installs into `~/local`:

| Component | Version | Needed for |
|-----------|---------|------------|
| Ruby      | 4.0.8   | |
| OpenSSL   | 3.5.8 (LTS) | `openssl`, HTTPS, `gem install` |
| libyaml   | 0.2.5   | YAML (`psych`) |
| zlib      | 1.3.1   | `zlib` |

Ruby goes in `~/local/ruby-4.0.8`, and the libraries go in `~/local/lib` and `~/local/include`. Nothing is installed system-wide, and no `sudo` is needed.

When the build finishes, the script confirms that OpenSSL, YAML, and zlib load and that an HTTPS request works. It then adds Ruby's `bin` directory to your `PATH` in `~/.zshrc` (or `~/.bash_profile` if you use bash).

## Requirements

- macOS on Intel or Apple silicon
- Xcode Command Line Tools. If they're missing, the script starts the installer and exits; run the script again once the installer finishes.
- An internet connection and some patience. OpenSSL and Ruby take the longest to compile.

## Usage

```bash
chmod u+x build_ruby.sh
./build_ruby.sh
```

Then open a new terminal and check:

```bash
ruby -v
```

## Changing versions

Edit the version variables at the top of the script:

```bash
RUBY_VERSION="4.0.8"
OPENSSL_VERSION="3.5.8"
ZLIB_VERSION="1.3.1"
YAML_VERSION="0.2.5"
```

Each Ruby version installs into its own `~/local/ruby-<version>` directory, so versions can sit side by side. When you switch, remove the old version's `PATH` line from your shell config.

You can rerun the script at any time. It reuses tarballs it already downloaded, re-downloads any that are corrupt, and doesn't add a duplicate `PATH` line.

## Apple silicon and Rosetta

If Terminal is set to "Open using Rosetta," you'll get an Intel build. Check the platform at the end of `ruby -v`: it should say `arm64-darwin` on Apple silicon, not `x86_64-darwin`.

## Uninstall

Everything lives under `~/local`. If you don't use that folder for anything else:

```bash
rm -rf ~/local
```

Then delete the `export PATH=".../local/ruby-..."` line from `~/.zshrc` or `~/.bash_profile`.
