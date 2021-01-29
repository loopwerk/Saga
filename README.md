# Saga

A static site generator, written in Swift.

## TODO

- Build image generator example
- Remove title from page body
- Add paginator support for list/tag/year writers
- Really should replace Ink and Splash
- Docs
- Tests

## Known limitations

- Stencil, the template language, doesn't support rendering computed properties (https://github.com/stencilproject/Stencil/issues/219). So if you extend `Page` with computed properties, you sadly won't be able to render them in your templates.
- Stencil's template inheritance doesn't support overriding blocks through multiple levels (https://github.com/stencilproject/Stencil/issues/275)
- Ink, the Markdown parser, is buggy and is missing features (https://github.com/JohnSundell/Ink/pull/49, https://github.com/JohnSundell/Ink/pull/63). Pull requests don't seem to get merged anymore, project not maintained?
- Splash, the syntax highlighter, only has support for Swift grammar. If you write articles with, let's say, JavaScript code blocks, they won't get properly highlighted.
