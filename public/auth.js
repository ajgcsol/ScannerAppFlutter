// Microsoft Authentication Configuration
const msalConfig = {
    auth: {
        clientId: "cd8d142c-8a24-40f3-ac2e-7f2da60e2965", // Replace with your Application (client) ID
        authority: "https://login.microsoftonline.com/40acb9f6-d0e3-4a23-9fc1-23e8e1ac0078", // Replace with your Directory (tenant) ID
        redirectUri: window.location.origin + "/auth/callback"
    },
    cache: {
        cacheLocation: "sessionStorage",
        storeAuthStateInCookie: true, // Better Edge compatibility
    },
    system: {
        allowNativeBroker: false, // Disable native broker for consistency
        windowHashTimeout: 9000, // Increase timeout for Edge
        iframeHashTimeout: 9000
    }
};

// Login request configuration
const loginRequest = {
    scopes: ["User.Read", "email", "openid", "profile"]
};

// Initialize MSAL instance
let msalInstance;
let currentUser = null;

// Initialize authentication
function initAuth() {
    try {
        msalInstance = new msal.PublicClientApplication(msalConfig);
        
        // Handle redirect response
        msalInstance.handleRedirectPromise().then(response => {
            if (response) {
                console.log("Login successful:", response);
                currentUser = response.account;
                showAuthenticatedUI();
                loadUserProfile();
            } else {
                // Check if user is already logged in
                const accounts = msalInstance.getAllAccounts();
                if (accounts.length > 0) {
                    currentUser = accounts[0];
                    showAuthenticatedUI();
                    loadUserProfile();
                } else {
                    // Show login UI after a delay to let main app load first
                    setTimeout(() => {
                        showLoginUI();
                    }, 1000);
                }
            }
        }).catch(error => {
            console.error("Auth error:", error);
            
            // Handle specific Edge/browser callback errors
            let errorMessage = 'Authentication failed';
            if (error.errorCode === 'user_cancelled') {
                errorMessage = 'Login was cancelled';
                console.info('User cancelled login');
            } else if (error.errorCode === 'access_denied') {
                errorMessage = 'Access denied. Please check your permissions.';
            } else if (error.message && error.message.includes('redirect')) {
                errorMessage = 'Authentication redirect error. Please try logging in again.';
                // Clear any cached auth state that might be corrupted
                try {
                    msalInstance.clearCache();
                    console.info('Cleared auth cache due to redirect error');
                } catch (clearError) {
                    console.warn('Could not clear cache:', clearError);
                }
            } else if (error.message && error.message.includes('network')) {
                errorMessage = 'Network error during authentication. Please check your connection.';
            } else {
                errorMessage = 'Authentication failed: ' + (error.message || error.errorCode || 'Unknown error');
            }
            
            // Show error message briefly, then show login
            if (typeof showMessage === 'function') {
                showMessage(errorMessage, 'error');
            } else {
                console.warn('Could not show message:', errorMessage);
            }
            
            // Don't block the app, just show login UI
            setTimeout(() => {
                showLoginUI();
            }, 1000);
        });
    } catch (error) {
        console.error("Auth initialization failed:", error);
        // Don't block the app if auth fails
        alert("Authentication system failed to initialize. Please refresh the page.");
    }
}

// Login function
async function login() {
    try {
        // Try popup first, fall back to redirect if it fails
        const response = await msalInstance.loginPopup(loginRequest);
        currentUser = response.account;
        showAuthenticatedUI();
        loadUserProfile();
    } catch (error) {
        console.error("Login popup failed, trying redirect:", error);
        // Fall back to redirect if popup fails
        msalInstance.loginRedirect(loginRequest);
    }
}

// Logout function
async function logout() {
    try {
        await msalInstance.logoutPopup({
            postLogoutRedirectUri: window.location.origin,
            mainWindowRedirectUri: window.location.origin
        });
        currentUser = null;
        showLoginUI();
    } catch (error) {
        console.error("Logout failed:", error);
        // Force logout anyway
        currentUser = null;
        showLoginUI();
    }
}

// Load user profile information
async function loadUserProfile() {
    try {
        console.log("Loading user profile...");
        const response = await msalInstance.acquireTokenSilent({
            ...loginRequest,
            account: currentUser
        });
        
        console.log("Got access token, fetching profile and photo...");
        
        // First get the profile
        const profileResponse = await fetch('https://graph.microsoft.com/v1.0/me', {
            headers: {
                'Authorization': `Bearer ${response.accessToken}`
            }
        });
        
        let userProfile = null;
        if (profileResponse.ok) {
            userProfile = await profileResponse.json();
            console.log("Profile data:", userProfile);
        } else {
            console.log("Profile response not ok:", profileResponse.status);
        }
        
        // Then try to get the photo
        let photoUrl = null;
        try {
            console.log("Attempting to fetch photo...");
            const photoResponse = await fetch('https://graph.microsoft.com/v1.0/me/photo/$value', {
                headers: {
                    'Authorization': `Bearer ${response.accessToken}`
                }
            });
            
            if (photoResponse.ok) {
                console.log("Photo response ok, creating blob URL...");
                const photoBlob = await photoResponse.blob();
                photoUrl = URL.createObjectURL(photoBlob);
                console.log("Photo URL created:", photoUrl);
            } else {
                console.log("Photo response failed:", photoResponse.status, photoResponse.statusText);
                // Try alternative photo endpoint
                const altPhotoResponse = await fetch('https://graph.microsoft.com/v1.0/me/photos/48x48/$value', {
                    headers: {
                        'Authorization': `Bearer ${response.accessToken}`
                    }
                });
                if (altPhotoResponse.ok) {
                    console.log("Alternative photo response ok...");
                    const photoBlob = await altPhotoResponse.blob();
                    photoUrl = URL.createObjectURL(photoBlob);
                    console.log("Alternative photo URL created:", photoUrl);
                } else {
                    console.log("Alternative photo also failed:", altPhotoResponse.status);
                }
            }
        } catch (photoError) {
            console.log("Photo fetch error:", photoError);
        }
        
        updateUserDisplay(userProfile, photoUrl);
    } catch (error) {
        console.error("Failed to load user profile:", error);
        // Try to update display with just the basic account info
        updateUserDisplay(null, null);
    }
}

// Update UI with user information
function updateUserDisplay(userProfile, photoUrl) {
    const userDisplayElement = document.getElementById('user-display');
    if (userDisplayElement) {
        // Use current user account info if userProfile is null
        const profile = userProfile || currentUser;
        const displayName = profile?.displayName || profile?.name || profile?.username || 'User';
        const email = profile?.mail || profile?.userPrincipalName || '';
        const jobTitle = profile?.jobTitle || '';
        
        // Create avatar - use photo if available, otherwise use initials
        let avatarContent;
        if (photoUrl) {
            avatarContent = `
                <img src="${photoUrl}" alt="Profile" style="width: 32px; height: 32px; border-radius: 50%; object-fit: cover; border: 2px solid rgba(255,255,255,0.3);">
            `;
        } else {
            const initials = displayName.charAt(0).toUpperCase();
            avatarContent = `
                <div style="width: 32px; height: 32px; border-radius: 50%; background: #1e3c72; display: flex; align-items: center; justify-content: center; color: white; font-weight: 600; font-size: 0.9rem; border: 2px solid rgba(255,255,255,0.3);">
                    ${initials}
                </div>
            `;
        }
        
        userDisplayElement.innerHTML = `
            <div style="display: flex; align-items: center; gap: 10px;">
                ${avatarContent}
                <div>
                    <div style="font-weight: 600; font-size: 0.9rem; color: white;">
                        ${displayName}
                    </div>
                    <div style="font-size: 0.8rem; opacity: 0.8; color: white;">
                        ${jobTitle || email}
                    </div>
                </div>
                <button class="header-btn" onclick="logout()" style="margin-left: 10px;">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path>
                        <polyline points="16 17 21 12 16 7"></polyline>
                        <line x1="21" y1="12" x2="9" y2="12"></line>
                    </svg>
                    Sign Out
                </button>
            </div>
        `;
    }
}

// Show login UI
function showLoginUI() {
    const appContainer = document.querySelector('.container');
    appContainer.innerHTML = `
        <div style="min-height: 100vh; display: flex; align-items: center; justify-content: center;">
            <div style="background: rgba(255, 255, 255, 0.95); backdrop-filter: blur(10px); border-radius: 20px; padding: 60px; text-align: center; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-width: 500px; width: 90%;">
                <div style="margin-bottom: 40px;">
                    <h1 style="color: #1e3c72; font-size: 2.5rem; margin-bottom: 10px; font-weight: 700;">inSession</h1>
                    <h2 style="color: #374151; font-size: 1.5rem; margin-bottom: 10px; font-weight: 600;">Admin Portal</h2>
                    <p style="color: #6b7280; font-size: 1.1rem;">Student Event Attendance System</p>
                </div>
                
                <div style="margin-bottom: 40px;">
                    <svg width="80" height="80" viewBox="0 0 64 64" style="margin-bottom: 20px;">
                        <rect x="8" y="8" width="48" height="48" rx="8" fill="#1e3c72"/>
                        <path d="M20 22 L20 42 M20 22 L28 22 M20 32 L28 32" stroke="white" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
                        <circle cx="38" cy="24" r="4" fill="white"/>
                        <path d="M34 42 C34 38 36 34 38 34 C40 34 42 38 42 42" stroke="white" stroke-width="3" stroke-linecap="round" fill="none"/>
                        <circle cx="48" cy="24" r="4" fill="#10b981"/>
                        <path d="M44 42 C44 38 46 34 48 34 C50 34 52 38 52 42" stroke="#10b981" stroke-width="3" stroke-linecap="round" fill="none"/>
                    </svg>
                    <p style="color: #6b7280; margin-bottom: 30px;">Sign in with your Microsoft 365 account to access the admin portal</p>
                </div>
                
                <button onclick="login()" style="
                    background: #1e3c72; 
                    color: white; 
                    border: none; 
                    padding: 16px 32px; 
                    border-radius: 10px; 
                    font-size: 1.1rem; 
                    font-weight: 600; 
                    cursor: pointer; 
                    transition: all 0.2s ease;
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    margin: 0 auto;
                    box-shadow: 0 4px 12px rgba(30, 60, 114, 0.3);
                " onmouseover="this.style.background='#163057'; this.style.transform='translateY(-2px)'" onmouseout="this.style.background='#1e3c72'; this.style.transform='translateY(0)'">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M5.8 3v4.6h4.6V3H5.8zm0 13.4h4.6V12H5.8v4.4zM12 3v4.6h4.6V3H12zm0 13.4h4.6V12H12v4.4zM5.8 8.2v3.6h4.6V8.2H5.8zm6.2 0v3.6h4.6V8.2H12z"/>
                    </svg>
                    Sign in with Microsoft 365
                </button>
                
                <div style="margin-top: 40px; padding-top: 30px; border-top: 1px solid #e5e7eb;">
                    <p style="color: #9ca3af; font-size: 0.9rem;">
                        Secure authentication powered by Microsoft Azure AD
                    </p>
                </div>
            </div>
        </div>
    `;
}

// Show authenticated UI
function showAuthenticatedUI() {
    // Hide login screen and show main app
    const appContainer = document.querySelector('.container');
    const mainContent = document.querySelector('.main-card');
    
    if (appContainer && appContainer.innerHTML.includes('Sign in with Microsoft 365')) {
        // We're showing login screen, need to reload to show main app
        location.reload();
    } else {
        // Main app is already loaded, just initialize it
        if (window.initializeApp) {
            window.initializeApp();
        }
    }
}

// Check if user is authenticated
function isAuthenticated() {
    return currentUser !== null;
}

// Get current user
function getCurrentUser() {
    return currentUser;
}

// Initialize auth when page loads
document.addEventListener('DOMContentLoaded', function() {
    initAuth();
});