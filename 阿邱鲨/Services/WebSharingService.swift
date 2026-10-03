//
//  WebSharingService.swift
//  阿邱鲨
//  局域网共享服务：通过浏览器上传漫画文件到手机
//

import Foundation
import Network
import UIKit

/// 局域网共享服务
final class WebSharingService {

    static let shared = WebSharingService()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var isRunning = false
    private(set) var port: UInt16 = 8080

    var onFileReceived: ((URL) -> Void)?
    var statusUpdate: ((String) -> Void)?

    private init() {}

    // MARK: - 启动/停止

    /// 启动服务器
    func start(port: UInt16 = 8080) {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            statusUpdate?("启动失败：\(error.localizedDescription)")
            return
        }

        self.port = port

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.statusUpdate?("服务已启动，端口 \(port)")
            case .failed(let error):
                self?.isRunning = false
                self?.statusUpdate?("服务失败：\(error.localizedDescription)")
            case .cancelled:
                self?.isRunning = false
                self?.statusUpdate?("服务已停止")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    /// 停止服务器
    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    // MARK: - 获取 IP 地址

    /// 获取设备的局域网 IP 地址
    func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - 处理连接

    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)

        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.closeConnection(connection)
                return
            }

            if let data = data, !data.isEmpty {
                self.handleRequest(data: data, connection: connection)
            } else if isComplete {
                self.closeConnection(connection)
            } else {
                self.receiveRequest(connection)
            }
        }
    }

    private func handleRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection, statusCode: 400, body: "Bad Request")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection, statusCode: 400, body: "Bad Request")
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection, statusCode: 400, body: "Bad Request")
            return
        }

        let method = parts[0]
        let path = parts[1]

        if method == "GET" && path == "/" {
            sendUploadPage(connection)
        } else if method == "POST" && path == "/upload" {
            handleUpload(data: data, connection: connection)
        } else {
            sendResponse(connection, statusCode: 404, body: "Not Found")
        }
    }

    // MARK: - 上传页面

    private func sendUploadPage(_ connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>阿邱鲨 - 局域网传输</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: #f5f5f7;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 20px;
                }
                .container {
                    background: white;
                    border-radius: 16px;
                    padding: 40px;
                    max-width: 500px;
                    width: 100%;
                    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
                }
                h1 {
                    font-size: 24px;
                    color: #1d1d1f;
                    margin-bottom: 8px;
                    text-align: center;
                }
                .subtitle {
                    color: #86868b;
                    text-align: center;
                    margin-bottom: 32px;
                    font-size: 14px;
                }
                .upload-area {
                    border: 2px dashed #d2d2d7;
                    border-radius: 12px;
                    padding: 48px 24px;
                    text-align: center;
                    cursor: pointer;
                    transition: all 0.2s;
                    margin-bottom: 20px;
                }
                .upload-area:hover, .upload-area.dragover {
                    border-color: #ff6b9d;
                    background: #fff0f5;
                }
                .upload-icon {
                    font-size: 48px;
                    margin-bottom: 16px;
                }
                .upload-text {
                    color: #1d1d1f;
                    font-size: 16px;
                    margin-bottom: 4px;
                }
                .upload-hint {
                    color: #86868b;
                    font-size: 13px;
                }
                input[type="file"] { display: none; }
                .btn {
                    width: 100%;
                    padding: 14px;
                    background: #ff6b9d;
                    color: white;
                    border: none;
                    border-radius: 10px;
                    font-size: 16px;
                    font-weight: 600;
                    cursor: pointer;
                    transition: opacity 0.2s;
                }
                .btn:hover { opacity: 0.9; }
                .btn:disabled {
                    background: #d2d2d7;
                    cursor: not-allowed;
                }
                .formats {
                    margin-top: 24px;
                    padding-top: 20px;
                    border-top: 1px solid #d2d2d7;
                }
                .formats h3 {
                    font-size: 14px;
                    color: #86868b;
                    margin-bottom: 10px;
                }
                .format-tags {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 6px;
                }
                .format-tag {
                    padding: 4px 10px;
                    background: #f5f5f7;
                    border-radius: 6px;
                    font-size: 12px;
                    color: #1d1d1f;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🦈 阿邱鲨</h1>
                <p class="subtitle">拖拽或选择漫画文件上传到手机</p>
                <input type="file" id="fileInput" multiple>
                <div class="formats">
                    <h3>支持格式</h3>
                    <div class="format-tags">
                        <span class="format-tag">CBZ</span>
                        <span class="format-tag">CBR</span>
                        <span class="format-tag">ZIP</span>
                        <span class="format-tag">RAR</span>
                        <span class="format-tag">PDF</span>
                        <span class="format-tag">EPUB</span>
                    </div>
                </div>
            </div>
        </body>
        </html>
        """

        sendResponse(connection, statusCode: 200, contentType: "text/html; charset=utf-8", body: html)
    }

    // MARK: - 处理上传

    private func handleUpload(data: Data, connection: NWConnection) {
        // 临时简化：只返回OK，等后续修复大文件上传
        sendResponse(connection, statusCode: 200, body: "OK")
    }

    // MARK: - 发送响应

    private func sendResponse(_ connection: NWConnection, statusCode: Int, contentType: String = "text/plain", body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        sendResponse(connection, statusCode: statusCode, contentType: contentType, bodyData: bodyData)
    }

    private func sendResponse(_ connection: NWConnection, statusCode: Int, contentType: String, bodyData: Data) {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Connection: close\r\n" +
                     "\r\n"

        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
            self?.closeConnection(connection)
        })
    }

    private func closeConnection(_ connection: NWConnection) {
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
}
