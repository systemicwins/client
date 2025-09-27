import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var showingRegistration = false
    
    var body: some View {
        if showingRegistration {
            RegistrationView(showingRegistration: $showingRegistration)
                .environmentObject(authManager)
        } else {
            loginContent
        }
    }
    
    private var loginContent: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App branding
            VStack(spacing: 20) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Relentless Trader")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Professional Trading Analytics")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Login form
            VStack(spacing: 20) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .disableAutocorrection(true)
                }
                
                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                // Remember me checkbox
                HStack {
                    Toggle("Remember me", isOn: $rememberMe)
                        .toggleStyle(.checkbox)
                    
                    Spacer()
                    
                    Button("Forgot Password?") {
                        // TODO: Implement forgot password
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                
                // Error message
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                // Account type indicator (shown after successful login)
                if authManager.isAuthenticated, let user = authManager.currentUser {
                    VStack(spacing: 4) {
                        if user.isRetail {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Retail Account - Free Access")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            }
                        } else if user.isPro {
                            HStack {
                                Image(systemName: "star.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Pro Account - Full Access")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                
                // Login button
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
                
                // Demo credentials hint for production mode
                if ProcessInfo.processInfo.environment["TRADER_ENV"] == "production" {
                    VStack(spacing: 4) {
                        Text("Demo Credentials:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("demo@demo.com / demo")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                }
                
                // Registration link
                HStack {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)
                    
                    Button("Sign Up") {
                        showingRegistration = true
                    }
                    .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onSubmit {
            login()
        }
    }
    
    private func login() {
        authManager.login(email: email, password: password)
    }
}

struct RegistrationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Binding var showingRegistration: Bool
    
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var agreeToTerms = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Header with title and close button
            HStack {
                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingRegistration = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 400)
            
            VStack(spacing: 20) {
                TextField("Full Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("I agree to the Terms of Service", isOn: $agreeToTerms)
                    .toggleStyle(.checkbox)
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: register) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        
                        Text("Create Account")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(authManager.isLoading || !isFormValid)
                
                Button(action: { showingRegistration = false }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .padding(.horizontal, 40)
    }
    
    private var isFormValid: Bool {
        return !name.isEmpty &&
               !email.isEmpty &&
               !password.isEmpty &&
               password == confirmPassword &&
               agreeToTerms
    }
    
    private func register() {
        authManager.register(email: email, password: password, name: name)
    }
}

