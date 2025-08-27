import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Trading Platform")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Professional Trading Client")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 50)
            
            Spacer()
            
            // Login Form
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            if showPassword {
                                TextField("Enter password", text: $password)
                                    .font(.body)
                            } else {
                                SecureField("Enter password", text: $password)
                                    .font(.body)
                            }
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: login) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                
                // Demo credentials info
                VStack(spacing: 4) {
                    Text("Demo Credentials")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Email: demo@demo.com  |  Password: demo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Footer
            VStack(spacing: 8) {
                Text("© 2024 Trading Platform")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Secure • Reliable • Professional")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onSubmit {
            login()
        }
    }
    
    private func login() {
        authManager.login(email: email, password: password)
    }
}