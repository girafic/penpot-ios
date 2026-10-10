# Extra icons

These icons fill gaps in Penpot's icon set: bell, key, credit card, camera, users, send,
unpin, add comment, template, unpublish, active filter and appearance. They follow
Penpot's own conventions: a 16×16 grid, a 1.33 stroke and round caps and joins.
`Scripts/fetch-penpot-icons.sh` turns them into template PDFs in
`Sources/Assets.xcassets/PenpotIcons/`.

Penpot's icons are Feather icons scaled to 2/3. Most of these are Feather shapes scaled
the same way, so they are covered by Feather's license:

> The MIT License (MIT)
>
> Copyright (c) 2013-2023 Cole Bemis
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this
> software and associated documentation files (the "Software"), to deal in the Software
> without restriction, including without limitation the rights to use, copy, modify,
> merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to the following
> conditions:
>
> The above copyright notice and this permission notice shall be included in all copies
> or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
> INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
> PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
> HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
> CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
> THE USE OR OTHER DEALINGS IN THE SOFTWARE.

`pin-off`, `comment-add` and `library-off` reuse Penpot's own `pin`, `comments` and
`library` paths with an added stroke. They are covered by Penpot's MPL-2.0.
