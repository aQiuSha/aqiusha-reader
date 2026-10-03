//
//  LockScreenView.swift
//  阿邱鲨
//
//  密码锁界面：支持数字密码和 Face ID/Touch ID
//

import SwiftUI
import LocalAuthentication

struct LockScreenView: View {

    let onUnlock: () -> Void

    @State private var password = ""
    @State private var shake = false
    @State private var errorMessage = ""
    @State private var showFaceID = true

    private let progressService = ProgressService.shared

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // App 图标
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 80)

                Text("阿邱鲨")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("请输入密码解锁")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 密码显示点
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < password.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.top, 20)
                .offset(x: shake ? -10 : 0)
                .animation(.default, value: shake)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                // 数字键盘
                VStack(spacing: 16) {
                    HStack(spacing: 40) {
                        numberButton("1")
                        numberButton("2")
                        numberButton("3")
                    }
                    HStack(spacing: 40) {
                        numberButton("4")
                        numberButton("5")
                        numberButton("6")
                    }
                    HStack(spacing: 40) {
                        numberButton("7")
                        numberButton("8")
                        numberButton("9")
                    }
                    HStack(spacing: 40) {
                        // Face ID 按钮
                        Button {
                            authenticateWithBiometrics()
                        } label: {
                            Image(systemName: "faceid")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 60, height: 60)
                        }
                        numberButton("0")
                        // 删除按钮
                        Button {
                            if !password.isEmpty {
                                password.removeLast()
                                errorMessage = ""
                            }
                        } label: {
                            Image(systemName: "delete.left.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            // 自动尝试 Face ID
            if showFaceID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    authenticateWithBiometrics()
                }
            }
        }
    }

    private func numberButton(_ number: String) -> some View {
        Button {
            if password.count < 4 {
                password += number
                errorMessage = ""
                if password.count == 4 {
                    verifyPassword()
                }
            }
        } label: {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 60, height: 60)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func verifyPassword() {
        if progressService.verifyPassword(password) {
            onUnlock()
        } else {
            errorMessage = "密码错误"
            shake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                shake = false
                password = ""
            }
        }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return
        }

        let reason = "解锁阿邱鲨"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                if success {
                    onUnlock()
                }
            }
        }
    }
}

// MARK: - 设置密码界面

struct SetPasswordView: View {

    let onComplete: (String) -> Void
    let onCancel: () -> Void

    @State private var firstPassword = ""
    @State private var secondPassword = ""
    @State private var step: Int = 1  // 1=输入新密码, 2=确认密码
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text(step == 1 ? "设置新密码" : "确认密码")
                    .font(.headline)
                    .padding(.top, 60)

                Text(step == 1 ? "请输入4位数字密码" : "请再次输入密码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 密码点
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < currentPassword.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                // 数字键盘
                VStack(spacing: 16) {
                    HStack(spacing: 40) {
                        numButton("1")
                        numButton("2")
                        numButton("3")
                    }
                    HStack(spacing: 40) {
                        numButton("4")
                        numButton("5")
                        numButton("6")
                    }
                    HStack(spacing: 40) {
                        numButton("7")
                        numButton("8")
                        numButton("9")
                    }
                    HStack(spacing: 40) {
                        Color.clear.frame(width: 60, height: 60)
                        numButton("0")
                        Button {
                            if !currentPassword.isEmpty {
                                currentPassword.removeLast()
                                errorMessage = ""
                            }
                        } label: {
                            Image(systemName: "delete.left.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 60)
            }
            .navigationTitle("设置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
            }
        }
    }

    private var currentPassword: Binding<String> {
        Binding(
            get: { step == 1 ? firstPassword : secondPassword },
            set: { newValue in
                if step == 1 { firstPassword = newValue }
                else { secondPassword = newValue }
            }
        )
    }

    private func numButton(_ number: String) -> some View {
        Button {
            if currentPassword.wrappedValue.count < 4 {
                currentPassword.wrappedValue += number
                errorMessage = ""
                if currentPassword.wrappedValue.count == 4 {
                    handleComplete()
                }
            }
        } label: {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 60, height: 60)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func handleComplete() {
        if step == 1 {
            step = 2
        } else {
            if firstPassword == secondPassword {
                onComplete(firstPassword)
            } else {
                errorMessage = "两次密码不一致"
                firstPassword = ""
                secondPassword = ""
                step = 1
            }
        }
    }
}

#Preview {
    LockScreenView { }
}
