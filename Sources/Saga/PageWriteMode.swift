public enum PageWriteMode {
  /// This will write a file like `content/about.md` as `deploy/about.html`
  case keepAsFile

  /// This will write a file like `content/about.md` as `deploy/about/index.html`
  case moveToSubfolder
}
