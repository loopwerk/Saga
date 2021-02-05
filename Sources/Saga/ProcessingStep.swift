import Foundation
import PathKit
import Stencil

internal class ProcessStep<M: Metadata, SiteMetadata: Metadata> {
  let folder: Path?
  let readers: [Reader<M>]
  let filter: (Page<M>) -> Bool
  let writers: [Writer<M, SiteMetadata>]
  var pages: [Page<M>]

  init(folder: Path?, readers: [Reader<M>], filter: @escaping (Page<M>) -> Bool, writers: [Writer<M, SiteMetadata>]) {
    self.folder = folder
    self.readers = readers
    self.filter = filter
    self.writers = writers
    self.pages = []
  }
}

internal class AnyProcessStep {
  let runReaders: () throws -> ()
  let runWriters: () throws -> ()

  init<M: Metadata, SiteMetadata: Metadata>(step: ProcessStep<M, SiteMetadata>, fileStorage: [FileContainer], inputPath: Path, outputPath: Path, environment: Environment, siteMetadata: SiteMetadata) {
    runReaders = {
      var pages = [Page<M>]()

      let unhandledFileContainers = fileStorage.filter { $0.handled == false }

      for unhandledFileContainer in unhandledFileContainers {
        let relativePath = try unhandledFileContainer.path.relativePath(from: inputPath)

        // Only work on files that match the folder (if any)
        if let folder = step.folder, !relativePath.string.starts(with: folder.string) {
          continue
        }

        // Pick the first reader that is able to work on this file, based on file extension
        guard let reader = step.readers.first(where: { $0.supportedExtensions.contains(relativePath.extension ?? "") }) else {
          continue
        }

        // Mark it as handled so that another step that works on a less specific folder doesn't also try to read it
        unhandledFileContainer.handled = true

        do {
          // Turn the file into a Page
          let page = try reader.convert(unhandledFileContainer.path, relativePath)

          // Store the generated Page
          if step.filter(page) {
            unhandledFileContainer.page = page
            pages.append(page)
          }
        } catch {
          // Couldn't convert the file into a Page, probably because of missing metadata
          // We still mark it has handled, otherwise another, less specific, read step might
          // pick it up with an EmptyMetadata, turning a broken page suddenly into a working page,
          // which is probably not what you want.
          print("❕File \(relativePath) failed conversion to Page<\(M.self)>, error: ", error)
          continue
        }
      }

      step.pages = pages
    }

    runWriters = {
      let allPages = fileStorage.compactMap(\.page)

      for writer in step.writers {
        try writer.write(step.pages, allPages, siteMetadata, { template, context, destination in
          let rendered = try environment.renderTemplate(name: template.string, context: context)
          try destination.parent().mkpath()
          try destination.write(rendered)
        }, outputPath, step.folder ?? "")
      }
    }
  }
}
