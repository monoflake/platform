# Media types

Facts on what an object is served as, each with its source; see `README.md`.

## Media types and extensions, read 2026-10-19

**mime-db groups extensions by the type they are served as, never by spelling.** In 1.54.0, 2522
types are listed, 1015 of them with extensions, 1239 extensions in all, and 48 extensions listed under
more than one type: `js` under `application/javascript` and `text/javascript`, `mp4` under
`application/mp4` and `video/mp4`. A type lists several: `image/jpeg` is `jpg`, `jpeg`, `jpe`, in that
order; `text/yaml` is `yaml`, `yml`; `text/markdown` is `md`, `markdown`; `text/plain` is `txt`,
`text`, `conf`, `def`, `list`, `log`, `in`, `ini`. `ts` is `video/mp2t` alone. So a type never leads
back to one extension, and the first listed is not always the long spelling. Asked by checklist A8.
Source: https://cdn.jsdelivr.net/npm/mime-db@1.54.0/db.json

**WHATWG's sniffing obeys the type given once no-sniff is set**, and counts HTML, XML and PDF among
the types a page could run, apart from its image, audio, video, font and archive patterns. Go's
`DetectContentType` follows it over the first 512 bytes and answers `application/octet-stream` when
it cannot tell. Asked by A8. Sources: https://mimesniff.spec.whatwg.org/ and
https://pkg.go.dev/net/http#DetectContentType

**Three-letter extensions are mostly four-letter names cut short.** CP/M and the FAT file system of
early MS-DOS and Windows allowed eight characters and an extension of three, and early Windows
programs wrote three; classic Mac OS allowed longer. Pairs named: `jpg` `jpeg`, `tif` `tiff`, `pct`
`pict`, `mpg` `mpeg`, `mid` `midi`, `aif` `aiff`, `wav` `wave`, `htm` `html`. The short ones
outlived the limit, Windows being the most used. Asked by A8. Source:
https://fileinfo.com/help/different_extensions

**MDN names the type of each common extension**, IANA's where one is registered: `md`
`text/markdown`, `js` and `mjs` `text/javascript` by RFC 9239, `flac` `audio/flac` where mime-db has
only `audio/x-flac`, `wav` `audio/wav` with `audio/wave` preferred by its container page, `ico`
`image/vnd.microsoft.icon`, `xml` `application/xml` by RFC 7303. `jxl`, `heic`, `tiff` and `mov`
are not shown by every browser: TIFF by Safari alone, QuickTime by Safari. Asked by A8. Sources:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types,
https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types and
https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Containers

**`Content-Security-Policy: sandbox` with no token makes a page show and do nothing.** Its origin is
opaque, so `document.cookie` and `localStorage` are out of reach and every same-origin check
fails; scripts do not run; a form is shown but never sent; popups and top-level navigation are
refused. It works only as a response header, never in `<meta>`, and has been in every browser since
November 2016. A response's policy populates the policy container of the document or worker made
from it; a page's own policy governs the requests it makes. Asked by A8. Sources:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/sandbox,
https://html.spec.whatwg.org/multipage/browsers.html#sandboxing and https://www.w3.org/TR/CSP3/

**Chrome shows a PDF blank when its response carries `sandbox`.** Jira, which sends the header on
attachments from 8.16, excludes `application/pdf` to make them load. Asked by A8. Sources:
https://support.atlassian.com/jira/kb/pdf-attachments-fail-to-load-in-chrome-on-jira-data-center/
and https://answers.sap.com/questions/13392550/chrome-blocking-pdf-content-accessed-via-media-url.html
