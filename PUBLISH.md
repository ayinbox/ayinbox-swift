# Publishing

Swift has no package registry step. Swift Package Manager resolves a package from its git repository and reads versions from semantic version tags, so a pushed `0.1.0` tag on a public repository is the release. There is no token to store anywhere.

## One-time setup

1. Make the repository `ayinbox/ayinbox-swift` public. Swift Package Manager and the Swift Package Index can only fetch a public repository.
2. Release `0.1.0` (see below) so there is a tag to index.
3. Submit the package to the Swift Package Index: open https://github.com/SwiftPackageIndex/PackageList/issues/new/choose, pick "Add Package(s)", and enter `https://github.com/ayinbox/ayinbox-swift.git`. A bot validates it (public, has a `Package.swift`, at least one semantic version tag, `swift package dump-package` works) and opens a pull request that the index maintainers merge, usually within a day.
4. Optionally claim the package on the index for the `ayinbox` organisation and add a `.spi.yml` if you want hosted DocC documentation.
5. Once the package is listed, update the README install section to `.package(url: "https://github.com/ayinbox/ayinbox-swift.git", from: "0.1.0")` and remove the "Not on the Swift Package Index yet" line.

## Every release

1. Bump `AyInbox.version` in `Sources/AyInbox/Client.swift` and add a `CHANGELOG.md` entry.
2. Commit, then tag and push. Use a plain semantic version (no `v` prefix), which is the form Swift Package Manager and the index expect:

   ```sh
   git tag 0.1.0
   git push origin 0.1.0
   ```

`.github/workflows/release.yml` runs on the tag, checks that it matches `AyInbox.version`, runs the tests on Linux and creates the GitHub release. The Swift Package Index picks up new tags on its own.

Never move or delete a published tag: Swift Package Manager pins the commit, and a moved tag breaks every project that resolved it.
