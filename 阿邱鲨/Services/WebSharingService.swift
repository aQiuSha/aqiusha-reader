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
    private var connections: [String: NWConnection] = [:]
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
        connections.values.forEach { $0.cancel() }
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
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("127.") {
                        address = ip
                    }
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - 处理连接

    private func handleConnection(_ connection: NWConnection) {
        let id = UUID().uuidString
        connections[id] = connection
        connection.start(queue: .main)
        
        var buffer = Data()
        receiveNext(connection: connection, id: id, buffer: &buffer)
    }

    private func receiveNext(connection: NWConnection, id: String, buffer: inout Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.closeConnection(connection, id: id)
                return
            }

            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            // 尝试解析完整请求
            if self.processRequestIfComplete(connection: connection, id: id, buffer: &buffer) {
                return
            }

            if isComplete {
                self.closeConnection(connection, id: id)
            } else {
                self.receiveNext(connection: connection, id: id, buffer: &buffer)
            }
        }
    }

    // MARK: - 请求解析

    private func processRequestIfComplete(connection: NWConnection, id: String, buffer: inout Data) -> Bool {
        // 找 header 结束位置
        guard let separator = "\r\n\r\n".data(using: .utf8),
              let separatorRange = buffer.range(of: separator) else {
            return false
        }

        let headerData = buffer.subdata(in: 0..<separatorRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return false
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return false }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return false }

        let method = parts[0]
        let path = parts[1]

        // 找 Content-Length
        var contentLength = 0
        for line in lines {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
                break
            }
        }

        // 检查 body 是否收完整
        let bodyStart = separatorRange.upperBound
        let expectedTotal = bodyStart + contentLength
        if buffer.count < expectedTotal {
            return false // 还没收完，继续等
        }

        // 请求完整了，开始处理
        let bodyData = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
        let fullRequestData = buffer.subdata(in: 0..<(bodyStart + contentLength))

        // 清空 buffer（简化处理，不支持pipeline）
        buffer.removeAll()

        handleRequest(method: method, path: path, fullData: fullRequestData, bodyData: bodyData, headerString: headerString, connection: connection, id: id)
        return true
    }

    private func handleRequest(method: String, path: String, fullData: Data, bodyData: Data, headerString: String, connection: NWConnection, id: String) {
        if method == "GET" && path == "/" {
            sendUploadPage(connection: connection, id: id)
        } else if method == "POST" && path == "/upload" {
            handleUpload(bodyData: bodyData, headerString: headerString, connection: connection, id: id)
        } else {
            sendResponse(connection: connection, id: id, statusCode: 404, body: "Not Found")
        }
    }

    // MARK: - 上传页面

    private func sendUploadPage(connection: NWConnection, id: String) {
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
                .file-list {
                    margin-top: 16px;
                    text-align: left;
                }
                .file-item {
                    padding: 10px 12px;
                    background: #f5f5f7;
                    border-radius: 8px;
                    margin-bottom: 8px;
                    font-size: 14px;
                    color: #1d1d1f;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }
                .status {
                    margin-top: 16px;
                    padding: 12px;
                    border-radius: 8px;
                    font-size: 14px;
                    text-align: center;
                    display: none;
                }
                .status.success {
                    background: #d4f4dd;
                    color: #1d7a35;
                    display: block;
                }
                .status.error {
                    background: #ffe5e5;
                    color: #d70015;
                    display: block;
                }
                .progress {
                    margin-top: 16px;
                    display: none;
                }
                .progress-bar {
                    height: 6px;
                    background: #d2d2d7;
                    border-radius: 3px;
                    overflow: hidden;
                }
                .progress-fill {
                    height: 100%;
                    background: #ff6b9d;
                    width: 0%;
                    transition: width 0.3s;
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

                <form id="uploadForm">
                    <div class="upload-area" id="uploadArea">
                        <div class="upload-icon">📁</div>
                        <div class="upload-text">点击或拖拽文件到此处</div>
                        <div class="upload-hint">支持多文件同时上传</div>
                        <input type="file" id="fileInput" multiple accept=".cbz,.cbr,.zip,.rar,.pdf,.epub,.7z,.tar,image/*">
                    </div>
                    <div class="file-list" id="fileList"></div>
                    <div class="progress" id="progress">
                        <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
                    </div>
                    <div class="status" id="status"></div>
                    <button type="submit" class="btn" id="uploadBtn" disabled>开始上传</button>
                </form>

                <div class="formats">
                    <h3>支持格式</h3>
                    <div class="format-tags">
                        <span class="format-tag">CBZ</span>
                        <span class="format-tag">CBR</span>
                        <span class="format-tag">ZIP</span>
                        <span class="format-tag">RAR</span>
                        <span class="format-tag">PDF</span>
                        <span class="format-tag">EPUB</span>
                        <span class="format-tag">图片</span>
                    </div>
                </div>
            </div>

            <script>
                const uploadArea = document.getElementById('uploadArea');
                const fileInput = document.getElementById('fileInput');
                const fileList = document.getElementById('fileList');
                const uploadBtn = document.getElementById('uploadBtn');
                const status = document.getElementById('status');
                const progress = document.getElementById('progress');
                const progressFill = document.getElementById('progressFill');
                const form = document.getElementById('uploadForm');

                let selectedFiles = [];

                uploadArea.addEventListener('click', () => fileInput.click());

                uploadArea.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    uploadArea.classList.add('dragover');
                });

                uploadArea.addEventListener('dragleave', () => {
                    uploadArea.classList.remove('dragover');
                });

                uploadArea.addEventListener('drop', (e) => {
                    e.preventDefault();
                    uploadArea.classList.remove('dragover');
                    handleFiles(e.dataTransfer.files);
                });

                fileInput.addEventListener('change', () => {
                    handleFiles(fileInput.files);
                });

                function handleFiles(files) {
                    selectedFiles = Array.from(files);
                    updateFileList();
                    uploadBtn.disabled = selectedFiles.length === 0;
                }

                function updateFileList() {
                    fileList.innerHTML = '';
                    selectedFiles.forEach((file, index) => {
                        const item = document.createElement('div');
                        item.className = 'file-item';
                        item.innerHTML = `<span>${file.name}</span><span>${(file.size / 1024 / 1024).toFixed(1)} MB</span>`;
                        fileList.appendChild(item);
                    });
                }

                form.addEventListener('submit', async (e) => {
                    e.preventDefault();
                    if (selectedFiles.length === 0) return;

                    uploadBtn.disabled = true;
                    progress.style.display = 'block';
                    status.style.display = 'none';

                    let successCount = 0;
                    let failCount = 0;

                    for (let i = 0; i < selectedFiles.length; i++) {
                        const file = selectedFiles[i];
                        const formData = new FormData();
                        formData.append('file', file);

                        try {
                            const response = await fetch('/upload', {
                                method: 'POST',
                                body: formData
                            });

                            if (response.ok) {
                                successCount++;
                            } else {
                                failCount++;
                            }
                        } catch (err) {
                            failCount++;
                        }

                        progressFill.style.width = ((i + 1) / selectedFiles.length * 100) + '%';
                    }

                    if (failCount === 0) {
                        status.className = 'status success';
                        status.textContent = `成功上传 ${successCount} 个文件，请在手机上查看`;
                    } else {
                        status.className = 'status error';
                        status.textContent = `成功 ${successCount} 个，失败 ${failCount} 个`;
                    }

                    uploadBtn.disabled = false;
                    selectedFiles = [];
                    updateFileList();
                });
            </script>
        </body>
        </html>
        """

        sendResponse(connection: connection, id: id, statusCode: 200, contentType: "text/html; charset=utf-8", body: html)
    }

    // MARK: - 处理上传

    private func handleUpload(bodyData: Data, headerString: String, connection: NWConnection, id: String) {
        // 从 header 里找 boundary
        guard let contentTypeLine = headerString.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-type:") }),
              let boundaryRange = contentTypeLine.range(of: "boundary=") else {
            sendResponse(connection: connection, id: id, statusCode: 400, body: "Missing boundary")
            return
        }

        let boundary = String(contentTypeLine[boundaryRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let boundaryData = ("--" + boundary).data(using: .utf8)!

        // 找第一个 boundary
        guard let firstBoundaryRange = bodyData.range(of: boundaryData) else {
            sendResponse(connection: connection, id: id, statusCode: 400, body: "No boundary found")
            return
        }

        let afterFirst = bodyData.subdata(in: firstBoundaryRange.upperBound..<bodyData.count)

        // 找 \r\n\r\n 分隔符
        guard let separator = "\r\n\r\n".data(using: .utf8),
              let separatorRange = afterFirst.range(of: separator) else {
            sendResponse(connection: connection, id: id, statusCode: 400, body: "Invalid multipart")
            return
        }

        // 提取文件名
        let headerPart = afterFirst.subdata(in: 0..<separatorRange.lowerBound)
        guard let headerString = String(data: headerPart, encoding: .utf8),
              let nameRange = headerString.range(of: "filename=\"") else {
            sendResponse(connection: connection, id: id, statusCode: 400, body: "No filename")
            return
        }
        let afterName = headerString[nameRange.upperBound...]
        guard let endRange = afterName.range(of: "\"") else {
            sendResponse(connection: connection, id: id, statusCode: 400, body: "Invalid filename")
            return
        }
        let fileName = String(afterName[..<endRange.lowerBound])

        // 提取文件内容
        let contentStart = separatorRange.upperBound
        var contentData = afterFirst.subdata(in: contentStart..<afterFirst.count)

        // 找结束 boundary
        if let endBoundaryRange = contentData.range(of: boundaryData) {
            contentData = contentData.subdata(in: 0..<endBoundaryRange.lowerBound)
            // 去掉结尾的 \r\n
            if contentData.count >= 2 {
                contentData = contentData.subdata(in: 0..<(contentData.count - 2))
            }
        }

        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try contentData.write(to: tempURL)
            statusUpdate?("收到文件：\(fileName) (\(contentData.count / 1024 / 1024) MB)")
            onFileReceived?(tempURL)
            sendResponse(connection: connection, id: id, statusCode: 200, body: "OK")
        } catch {
            sendResponse(connection: connection, id: id, statusCode: 500, body: "Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - 发送响应

    private func sendResponse(connection: NWConnection, id: String, statusCode: Int, contentType: String = "text/plain", body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        sendResponse(connection: connection, id: id, statusCode: statusCode, contentType: contentType, bodyData: bodyData)
    }

    private func sendResponse(connection: NWConnection, id: String, statusCode: Int, contentType: String, bodyData: Data) {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Access-Control-Allow-Origin: *\r\n" +
                     "Connection: close\r\n" +
                     "\r\n"

        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { [weak self] _ in
            self?.closeConnection(connection, id: id)
        })
    }

    private func closeConnection(_ connection: NWConnection, id: String) {
        connection.cancel()
        connections.removeValue(forKey: id)
    }
}
