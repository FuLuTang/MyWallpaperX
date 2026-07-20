from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TRANSFORMER_SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperResponseTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperHTMLTransformer.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperCSSImportTransformer.swift",
]


class WebResponseTransformerTests(unittest.TestCase):
    def test_production_transformers(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")

        harness = textwrap.dedent(
            r'''
            import Foundation

            func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
                guard condition() else {
                    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
                    exit(1)
                }
            }

            func markerCount(_ value: String) -> Int {
                value.components(separatedBy: "data-mwx-deferred-stylesheet").count - 1
            }

            let googleLink = #"<link rel='stylesheet' href='http://fonts.googleapis.com/css2?family=Inter'>"#
            let transformedGoogleLink = WebWallpaperHTMLTransformer.transform(googleLink)
            expect(transformedGoogleLink.contains("rel='preload'"), "Google Fonts link should become a preload")
            expect(transformedGoogleLink.contains("href='https://fonts.googleapis.com/css2?family=Inter'"), "Google Fonts HTTP links should upgrade to HTTPS")
            expect(transformedGoogleLink.contains("as=\"style\""), "deferred link should identify a style preload")
            expect(transformedGoogleLink.contains("data-mwx-deferred-stylesheet=\"stylesheet\""), "original rel should be retained")

            let protocolRelativeLink = #"<link href="//fonts.googleapis.com/css2?family=Fira+Code" rel="stylesheet">"#
            let transformedProtocolRelativeLink = WebWallpaperHTMLTransformer.transform(protocolRelativeLink)
            expect(transformedProtocolRelativeLink.contains(#"href="https://fonts.googleapis.com/css2?family=Fira+Code""#), "protocol-relative Google Fonts links should become absolute HTTPS URLs")
            expect(transformedProtocolRelativeLink.contains(#"rel="preload""#), "href-before-rel links should still replace rel correctly")
            expect(markerCount(transformedProtocolRelativeLink) == 1, "protocol-relative Google Fonts links should transform once")

            let quotedGreaterThan = #"<link title='a > b' rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Roboto'>"#
            let transformedQuotedGreaterThan = WebWallpaperHTMLTransformer.transform(quotedGreaterThan)
            expect(transformedQuotedGreaterThan.contains("title='a > b'"), "quoted greater-than should not truncate a tag")
            expect(markerCount(transformedQuotedGreaterThan) == 1, "quoted greater-than link should transform once")

            let rawText = #"""
            <!-- <link rel="stylesheet" href="https://fonts.googleapis.com/comment"> -->
            <script>const template = '<link rel="stylesheet" href="https://fonts.googleapis.com/script">';</script>
            <style>.sample::before { content: '<link rel="stylesheet" href="https://fonts.googleapis.com/style">'; }</style>
            <textarea><link rel="stylesheet" href="https://fonts.googleapis.com/textarea"></textarea>
            <title><link rel="stylesheet" href="https://fonts.googleapis.com/title"></title>
            <link rel="stylesheet" href="https://fonts.googleapis.com/real">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(rawText)) == 1, "raw text and comments must remain untouched")

            let expandedRawText = #"""
            <xmp><link rel="stylesheet" href="https://fonts.googleapis.com/xmp"></xmp>
            <iframe><link rel="stylesheet" href="https://fonts.googleapis.com/iframe-fallback"></iframe>
            <noembed><link rel="stylesheet" href="https://fonts.googleapis.com/noembed"></noembed>
            <noframes><link rel="stylesheet" href="https://fonts.googleapis.com/noframes"></noframes>
            <noscript><link rel="stylesheet" href="https://fonts.googleapis.com/noscript"></noscript>
            <link rel="stylesheet" href="https://fonts.googleapis.com/after-raw-text">
            """#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(expandedRawText)) == 1, "legacy raw-text and iframe fallback content must remain untouched")

            let plaintext = #"<link rel="stylesheet" href="https://fonts.googleapis.com/before-plaintext"><plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/inside-plaintext"></plaintext><link rel="stylesheet" href="https://fonts.googleapis.com/after-plaintext-close">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(plaintext)) == 1, "plaintext should consume the rest of its parent document")

            let iframeDocument = #"<link rel="stylesheet" href="https://fonts.googleapis.com/iframe-document">"#
            expect(markerCount(WebWallpaperHTMLTransformer.transform(iframeDocument)) == 1, "an independently loaded iframe document should still transform")

            let skippedLinks = [
                #"<link rel="alternate stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" disabled>"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" media="print">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" as="style">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" onload="ready()">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" data-mwx-deferred-stylesheet="stylesheet">"#,
                #"<link rel="stylesheet" data-href="https://fonts.googleapis.com/a">"#,
                #"<link data-rel="stylesheet" href="https://fonts.googleapis.com/a">"#,
                #"<link rel="stylesheet" href="https://cdn.example.com/business.css">"#,
                #"<link rel="stylesheet" href="https://fonts.googleapis.com/a" type="text/plain">"#,
            ]
            for (index, link) in skippedLinks.enumerated() {
                expect(WebWallpaperHTMLTransformer.transform(link) == link, "skip boundary \(index) should remain byte-for-byte unchanged")
            }

            let optedIn = #"<link rel="stylesheet" href="http://127.0.0.1:48765/slow.css" data-mwx-defer-stylesheet>"#
            let transformedOptedIn = WebWallpaperHTMLTransformer.transform(optedIn)
            expect(markerCount(transformedOptedIn) == 1, "explicit opt-in should defer a non-Google stylesheet")
            expect(transformedOptedIn.contains(#"href="http://127.0.0.1:48765/slow.css""#), "explicit non-Google opt-in should preserve its authored URL")

            let css = #"""
            @charset "UTF-8";
            /* leading comment */
            @layer reset;
            @import url("http://fonts.googleapis.com/css2?family=Inter");
            body { color: black; }
            @import "https://fonts.googleapis.com/css2?family=Late";
            """#
            let transformedCSS = WebWallpaperCSSImportTransformer.transform(css)
            expect(transformedCSS.contains(#"@import url("https://fonts.googleapis.com/css2?family=Inter") not all;"#), "eligible Google import should be deferred and upgraded to HTTPS")
            expect(transformedCSS.contains(#"@import "https://fonts.googleapis.com/css2?family=Late";"#), "late import should remain untouched")

            let supportedGoogleImports = [
                #"@import url(https://fonts.googleapis.com/css2?family=Roboto);"#,
                #"@import "//fonts.googleapis.com/css2?family=Lato";"#,
                #"@import url('//fonts.googleapis.com/css2?family=Nunito');"#,
                #"@import url(//fonts.googleapis.com/css2?family=Oswald);"#,
            ]
            for (index, statement) in supportedGoogleImports.enumerated() {
                let transformed = WebWallpaperCSSImportTransformer.transform(statement)
                expect(transformed.hasPrefix(#"@import url("https://fonts.googleapis.com/"#), "supported Google import \(index) should normalize to HTTPS")
                expect(transformed.hasSuffix(#"") not all;"#), "supported Google import \(index) should become nonblocking")
            }

            let cssStringOnly = #"body::before { content: '@import "https://fonts.googleapis.com/not-a-rule";'; }"#
            expect(WebWallpaperCSSImportTransformer.transform(cssStringOnly) == cssStringOnly, "CSS strings must remain untouched")
            let conditionalImport = #"@import url("https://fonts.googleapis.com/css2?family=Print") print;"#
            expect(WebWallpaperCSSImportTransformer.transform(conditionalImport) == conditionalImport, "conditional imports must retain their authored media semantics")
            let protocolRelativeConditionalImport = #"@import url(//fonts.googleapis.com/css2?family=Layered) layer(fonts);"#
            expect(WebWallpaperCSSImportTransformer.transform(protocolRelativeConditionalImport) == protocolRelativeConditionalImport, "protocol-relative imports with authored conditions must remain untouched")

            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/index.HTML")), "HTML should be transformable")
            expect(WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/site.css")), "CSS should be transformable")
            expect(!WebWallpaperResponseTransformer.supportsTransformation(for: URL(fileURLWithPath: "/tmp/video.mp4")), "binary media must not be transformed")

            print("Web response transformer tests passed")
            '''
        )

        with tempfile.TemporaryDirectory(prefix="mwx-web-transformer-tests-") as directory:
            temporary = Path(directory)
            harness_path = temporary / "main.swift"
            binary_path = temporary / "WebResponseTransformerTests"
            harness_path.write_text(harness, encoding="utf-8")
            subprocess.run(
                [swiftc, *(str(path) for path in TRANSFORMER_SOURCES), str(harness_path), "-o", str(binary_path)],
                cwd=ROOT,
                check=True,
            )
            completed = subprocess.run(
                [str(binary_path)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("tests passed", completed.stdout)


if __name__ == "__main__":
    unittest.main()
