import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1

final class DevServer {
  private let outputPath: String
  private let port: Int
  private let group: MultiThreadedEventLoopGroup
  private var channel: Channel?
  private let sseConnections = SSEConnectionStore()

  init(outputPath: String, port: Int) {
    self.outputPath = outputPath
    self.port = port
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
  }

  func start() throws {
    let outputPath = self.outputPath
    let sseConnections = self.sseConnections
    let baseDir = FileManager.default.currentDirectoryPath

    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(HTTPHandler(outputPath: baseDir + "/" + outputPath, sseConnections: sseConnections))
        }
      }

    channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
    try channel?.closeFuture.wait()
  }

  func stop() {
    try? channel?.close().wait()
    try? group.syncShutdownGracefully()
  }

  func sendReload() {
    sseConnections.sendReload()
  }
}

final class SSEConnectionStore: @unchecked Sendable {
  private var connections: [Channel] = []
  private let lock = NSLock()

  func add(_ channel: Channel) {
    lock.lock()
    connections.append(channel)
    lock.unlock()
  }

  func remove(_ channel: Channel) {
    lock.lock()
    connections.removeAll { $0 === channel }
    lock.unlock()
  }

  func sendReload() {
    lock.lock()
    let current = connections
    lock.unlock()

    for channel in current {
      var buffer = channel.allocator.buffer(capacity: 64)
      buffer.writeString("data: reload\n\n")
      channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
    }
  }
}

private final class HTTPHandler: ChannelInboundHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let outputPath: String
  private let sseConnections: SSEConnectionStore
  private var requestURI: String = "/"

  init(outputPath: String, sseConnections: SSEConnectionStore) {
    self.outputPath = outputPath
    self.sseConnections = sseConnections
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = unwrapInboundIn(data)

    switch part {
    case .head(let request):
      requestURI = request.uri

    case .body:
      break

    case .end:
      handleRequest(uri: requestURI, context: context)
    }
  }

  private func handleRequest(uri: String, context: ChannelHandlerContext) {
    // SSE endpoint for auto-reload
    if uri == "/_reload" {
      handleSSE(context: context)
      return
    }

    // Static file serving
    let filePath = resolveFilePath(uri: uri)

    guard let filePath = filePath,
          FileManager.default.fileExists(atPath: filePath),
          let data = FileManager.default.contents(atPath: filePath)
    else {
      sendNotFound(context: context)
      return
    }

    let contentType = mimeType(for: filePath)
    let isHTML = contentType == "text/html"

    var responseData: Data
    if isHTML, let html = String(data: data, encoding: .utf8) {
      responseData = Data(injectReloadScript(into: html).utf8)
    } else {
      responseData = data
    }

    var headers = HTTPHeaders()
    headers.add(name: "Content-Type", value: contentType)
    headers.add(name: "Content-Length", value: "\(responseData.count)")
    headers.add(name: "Cache-Control", value: "no-cache")

    let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
    context.write(wrapOutboundOut(.head(head)), promise: nil)

    var buffer = context.channel.allocator.buffer(capacity: responseData.count)
    buffer.writeBytes(responseData)
    context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
  }

  private func handleSSE(context: ChannelHandlerContext) {
    var headers = HTTPHeaders()
    headers.add(name: "Content-Type", value: "text/event-stream")
    headers.add(name: "Cache-Control", value: "no-cache")
    headers.add(name: "Connection", value: "keep-alive")

    let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
    context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)

    sseConnections.add(context.channel)

    context.channel.closeFuture.whenComplete { [weak self] _ in
      self?.sseConnections.remove(context.channel)
    }
  }

  private func resolveFilePath(uri: String) -> String? {
    let path = uri.split(separator: "?").first.map(String.init) ?? uri
    let fileManager = FileManager.default

    // Direct file match
    let directPath = outputPath + path
    if fileManager.fileExists(atPath: directPath) {
      var isDir: ObjCBool = false
      fileManager.fileExists(atPath: directPath, isDirectory: &isDir)
      if !isDir.boolValue {
        return directPath
      }
      // It's a directory, look for index.html
      let indexPath = directPath.hasSuffix("/") ? directPath + "index.html" : directPath + "/index.html"
      if fileManager.fileExists(atPath: indexPath) {
        return indexPath
      }
    }

    // Try with .html extension
    let htmlPath = directPath + ".html"
    if fileManager.fileExists(atPath: htmlPath) {
      return htmlPath
    }

    // Try path/index.html
    let indexPath = directPath.hasSuffix("/") ? directPath + "index.html" : directPath + "/index.html"
    if fileManager.fileExists(atPath: indexPath) {
      return indexPath
    }

    return nil
  }

  private func sendNotFound(context: ChannelHandlerContext) {
    let body = "404 Not Found"
    var headers = HTTPHeaders()
    headers.add(name: "Content-Type", value: "text/plain")
    headers.add(name: "Content-Length", value: "\(body.utf8.count)")

    let head = HTTPResponseHead(version: .http1_1, status: .notFound, headers: headers)
    context.write(wrapOutboundOut(.head(head)), promise: nil)

    var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
    buffer.writeString(body)
    context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
  }

  private func injectReloadScript(into html: String) -> String {
    let script = """
    <script>new EventSource('/_reload').onmessage=function(){location.reload()}</script>
    """
    if let range = html.range(of: "</body>", options: .backwards) {
      return html.replacingCharacters(in: range, with: script + "</body>")
    }
    return html + script
  }

  private func mimeType(for path: String) -> String {
    let ext: String
    if let dotIndex = path.lastIndex(of: ".") {
      ext = String(path[path.index(after: dotIndex)...]).lowercased()
    } else {
      ext = ""
    }
    switch ext {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js": return "application/javascript"
    case "json": return "application/json"
    case "xml": return "application/xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "webp": return "image/webp"
    case "ico": return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    case "otf": return "font/otf"
    case "pdf": return "application/pdf"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
  }
}
