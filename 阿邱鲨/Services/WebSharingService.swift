//
//  WebSharingService.swift
//  阿邱鲨
//
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
                    border-color: #007aff;
                    background: #f0f7ff;
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
                    background: #007aff;
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
                    background: #007aff;
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
                        <span class="format-tag">文件夹</span>
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

        sendResponse(connection, statusCode: 200, contentType: "text/html; charset=utf-8", body: html)
    }

    // MARK: - 处理上传

    private func handleUpload(data: Data, connection: NWConnection) {
        // 解析 multipart/form-data
        guard let contentType = extractHeader(data: data, header: "Content-Type") else {
            sendResponse(connection, statusCode: 400, body: "Missing Content-Type")
            return
        }

        guard let boundary = extractBoundary(contentType: contentType) else {
            sendResponse(connection, statusCode: 400, body: "Invalid boundary")
            return
        }

        // 分离 header 和 body
        guard let separator = "\r\n\r\n".data(using: .utf8),
              let separatorRange = data.range(of: separator) else {
            sendResponse(connection, statusCode: 400, body: "Invalid request")
            return
        }

        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)

        // 解析文件
        guard let fileData = extractFileData(from: bodyData, boundary: boundary),
              let fileName = extractFileName(from: bodyData, boundary: boundary) else {
            sendResponse(connection, statusCode: 400, body: "No file found")
            return
        }

        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileName)

        do {
            try fileData.write(to: tempURL)
            statusUpdate?("收到文件：\(fileName)")
            onFileReceived?(tempURL)
            sendResponse(connection, statusCode: 200, body: "OK")
        } catch {
            sendResponse(connection, statusCode: 500, body: "Save failed")
        }
    }

    private func extractHeader(data: Data, header: String) -> String? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        let lines = string.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix(header.lowercased() + ":") {
                return String(line.dropFirst(header.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractBoundary(contentType: String) -> String? {
        guard let range = contentType.range(of: "boundary=") else { return nil }
        return String(contentType[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func extractFileName(from data: Data, boundary: String) -> String? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        guard let nameRange = string.range(of: "filename=\"") else { return nil }
        let afterName = string[nameRange.upperBound...]
        guard let endRange = afterName.range(of: "\"") else { return nil }
        return String(afterName[..<endRange.lowerBound])
    }

    private func extractFileData(from data: Data, boundary: String) -> Data? {
        guard let boundaryData = ("--" + boundary).data(using: .utf8) else { return nil }

        // 找到第一个 boundary 后的内容
        guard let firstBoundary = data.range(of: boundaryData) else { return nil }
        let afterFirst = data.subdata(in: firstBoundary.upperBound..<data.count)

        // 找到 \r\n\r\n 分隔符（header 结束）
        guard let separator = "\r\n\r\n".data(using: .utf8),
              let separatorRange = afterFirst.range(of: separator) else { return nil }

        let contentStart = separatorRange.upperBound
        let contentData = afterFirst.subdata(in: contentStart..<afterFirst.count)

        // 找到结束 boundary
        guard let endBoundary = contentData.range(of: boundaryData) else {
            // 没有结束 boundary，可能数据不完整，返回剩余内容
            return contentData
        }

        // 去掉结尾的 \r\n
        var fileData = contentData.subdata(in: 0..<endBoundary.lowerBound)
        if fileData.count >= 2 {
            fileData = fileData.subdata(in: 0..<(fileData.count - 2))
        }

        return fileData
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
