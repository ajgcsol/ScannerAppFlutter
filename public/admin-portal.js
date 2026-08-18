// Backend is Azure Functions + Cosmos DB. azure-db.js (loaded first) supplies
// the firebase.firestore() compat surface this file is written against, so the
// data access below is unchanged. Connection details live in
// window.INSESSION_CONFIG in index.html.
firebase.initializeApp();
const db = firebase.firestore();
const storage = firebase.storage();

// Global variables
let currentStudents = [];
let csvData = null;
let studentImageCache = new Map();

// Tab management
function showTab(tabName) {
    // Hide all tab panes
    document.querySelectorAll('.tab-pane').forEach(pane => {
        pane.classList.remove('active');
    });
    
    // Remove active class from all tabs
    document.querySelectorAll('.tab').forEach(tab => {
        tab.classList.remove('active');
    });
    
    // Show selected tab pane
    document.getElementById(tabName + '-tab').classList.add('active');
    
    // Add active class to clicked tab
    event.target.classList.add('active');
    
    // Load data for specific tabs
    if (tabName === 'manage') {
        loadStudentData();
    } else if (tabName === 'analytics') {
        console.log('🔄 Analytics tab clicked, loading analytics...');
        if (window.isAuthenticated && window.isAuthenticated()) {
            loadAnalytics();
        } else {
            console.log('⚠️ Not authenticated, waiting for authentication...');
            setTimeout(() => {
                if (window.isAuthenticated && window.isAuthenticated()) {
                    loadAnalytics();
                } else {
                    console.log('❌ Still not authenticated after delay');
                }
            }, 1000);
        }
    } else if (tabName === 'events') {
        loadEvents();
    }
}

// File upload handling
function handleDragOver(event) {
    event.preventDefault();
    event.currentTarget.classList.add('dragover');
}

function handleDrop(event) {
    event.preventDefault();
    event.currentTarget.classList.remove('dragover');
    
    const files = event.dataTransfer.files;
    if (files.length > 0) {
        handleFile(files[0]);
    }
}

function handleFileSelect(event) {
    const file = event.target.files[0];
    if (file) {
        handleFile(file);
    }
}

function handleFile(file) {
    if (!file.name.toLowerCase().endsWith('.csv')) {
        showMessage('Please select a CSV file.', 'error');
        return;
    }
    
    // Show file info
    document.getElementById('file-name').textContent = file.name;
    document.getElementById('file-size').textContent = formatFileSize(file.size);
    document.getElementById('file-preview').classList.remove('hidden');
    
    // Read and preview CSV
    const reader = new FileReader();
    reader.onload = function(e) {
        const csvText = e.target.result;
        parseAndPreviewCSV(csvText);
    };
    reader.readAsText(file);
}

function parseAndPreviewCSV(csvText) {
    const lines = csvText.split('\n');
    const headers = lines[0].split(',').map(h => h.trim());
    const rows = lines.slice(1).filter(line => line.trim().length > 0);
    
    // Store parsed data
    csvData = {
        headers: headers,
        rows: rows.map(row => {
            const values = row.split(',').map(v => v.trim().replace(/^"|"$/g, ''));
            const student = {};
            headers.forEach((header, index) => {
                student[header.toLowerCase().replace(/\s+/g, '')] = values[index] || '';
            });
            return student;
        })
    };
    
    // Create preview table
    let tableHTML = '<table class="preview-table"><thead><tr>';
    headers.forEach(header => {
        tableHTML += `<th>${header}</th>`;
    });
    tableHTML += '</tr></thead><tbody>';
    
    // Show first 5 rows as preview
    const previewRows = csvData.rows.slice(0, 5);
    previewRows.forEach(student => {
        tableHTML += '<tr>';
        headers.forEach(header => {
            const key = header.toLowerCase().replace(/\s+/g, '');
            tableHTML += `<td>${student[key] || ''}</td>`;
        });
        tableHTML += '</tr>';
    });
    
    if (csvData.rows.length > 5) {
        tableHTML += `<tr><td colspan="${headers.length}" style="text-align: center; font-style: italic; color: #718096;">... and ${csvData.rows.length - 5} more rows</td></tr>`;
    }
    
    tableHTML += '</tbody></table>';
    
    document.getElementById('csv-preview').innerHTML = `
        <h4 style="color: #2d3748; margin-bottom: 15px;">Preview (${csvData.rows.length} students total)</h4>
        ${tableHTML}
    `;
    
    showMessage(`Successfully parsed ${csvData.rows.length} student records.`, 'success');
}

function clearFile() {
    document.getElementById('csvFile').value = '';
    document.getElementById('file-preview').classList.add('hidden');
    csvData = null;
    clearMessage();
}

async function uploadData() {
    if (!csvData) {
        showMessage('Please select a CSV file first.', 'error');
        return;
    }
    
    const uploadBtn = document.getElementById('upload-btn');
    uploadBtn.innerHTML = '<span class="loading"></span>Uploading...';
    uploadBtn.disabled = true;
    
    try {
        const batch = db.batch();
        let successCount = 0;
        let skippedCount = 0;
        
        for (const student of csvData.rows) {
            // Validate required fields only (removed program and year from requirements)
            const studentId = student.studentid || student.id || '';
            const firstName = student.firstname || student.first_name || '';
            const lastName = student.lastname || student.last_name || '';
            const email = student.email || '';
            
            // Only require studentId, firstName, and lastName
            if (!studentId || !firstName || !lastName) {
                console.warn('Skipping incomplete record (missing required fields):', student);
                skippedCount++;
                continue;
            }
            
            const studentDoc = {
                studentId: studentId,
                firstName: firstName,
                lastName: lastName,
                email: email || '', // Email can be empty
                program: student.program || '', // Optional field
                year: student.year || '', // Optional field
                uploadedAt: firebase.firestore.FieldValue.serverTimestamp(),
                active: true
            };
            
            const docRef = db.collection('students').doc(studentId);
            batch.set(docRef, studentDoc, { merge: true });
            successCount++;
        }
        
        await batch.commit();
        
        let message = `Successfully uploaded ${successCount} student records to the database.`;
        if (skippedCount > 0) {
            message += ` (${skippedCount} records skipped due to missing required fields)`;
        }
        showMessage(message, 'success');
        
        // Update analytics
        await updateAnalytics();
        
        clearFile();
        
    } catch (error) {
        console.error('Upload error:', error);
        showMessage('Error uploading data: ' + error.message, 'error');
    } finally {
        uploadBtn.innerHTML = 'Upload to Database';
        uploadBtn.disabled = false;
    }
}

async function loadStudentData() {
    try {
        console.log('Loading student data with photo information...');
        
        // Use the new API that includes photo data
        const response = await fetch('https://insession-api-fc.azurewebsites.net/getStudentsWithPhotos?includePhotos=true');
        
        if (!response.ok) {
            throw new Error('Failed to fetch student data');
        }
        
        const data = await response.json();
        currentStudents = data.students || [];
        
        console.log(`Loaded ${currentStudents.length} students`);
        displayStudents(currentStudents);
        updatePhotoFilterCount();
        
    } catch (error) {
        console.error('Error loading students:', error);
        showMessage('Error loading student data: ' + error.message, 'error');
        
        // Fallback to direct Firestore query
        try {
            const studentsSnapshot = await db.collection('students')
                .orderBy('lastName')
                .limit(100)
                .get();
            
            currentStudents = studentsSnapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                hasPhoto: doc.data().hasPhoto || false
            }));
            
            displayStudents(currentStudents);
            updatePhotoFilterCount();
            
        } catch (fallbackError) {
            console.error('Fallback query also failed:', fallbackError);
        }
    }
}

function displayStudentsTableLegacy(students) { // superseded by the card renderer below
    // Try both possible tbody IDs for compatibility
    const tbody = document.getElementById('students-tbody') || document.querySelector('#students-table tbody');
    
    if (students.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="6" style="text-align: center; padding: 40px; color: #718096;">
                    No students found. Upload CSV data to get started.
                </td>
            </tr>
        `;
        return;
    }
    
    // Clear existing content
    tbody.innerHTML = '';
    
    students.forEach(student => {
        const row = document.createElement('tr');
        
        // Photo column
        const photoCell = document.createElement('td');
        photoCell.style.padding = '12px';
        const imageElement = createStudentImageElement(student.studentId, '40px');
        photoCell.appendChild(imageElement);
        
        // Student data columns
        row.innerHTML = `
            <td>${student.studentId || ''}</td>
            <td>${student.firstName || ''}</td>
            <td>${student.lastName || ''}</td>
            <td>${student.email || ''}</td>
            <td>
                <div style="display: flex; align-items: center; gap: 8px;">
                    <select id="student-action-${student.id}" class="btn btn-secondary" style="padding: 6px 10px; font-size: 0.9rem; cursor: pointer;">
                        <option value="">Select Action...</option>
                        <option value="view">View Details</option>
                        <option value="edit">Edit Student</option>
                        <option value="export">Export Data</option>
                        <option value="delete">Delete Student</option>
                    </select>
                    <button class="btn btn-primary" onclick="executeStudentAction('${student.id}', '${student.studentId}', '${(student.firstName || '').replace(/'/g, "\\'")}', '${(student.lastName || '').replace(/'/g, "\\'")}')" 
                            style="padding: 6px 12px; font-size: 0.9rem;">
                        Go
                    </button>
                </div>
            </td>
        `;
        
        // Insert photo cell as first column
        row.insertBefore(photoCell, row.firstChild);
        tbody.appendChild(row);
    });
}

function searchStudents() {
    const searchTerm = document.getElementById('search-input').value.toLowerCase();
    
    if (!searchTerm) {
        displayStudents(currentStudents);
        return;
    }
    
    const filteredStudents = currentStudents.filter(student => 
        (student.studentId || '').toLowerCase().includes(searchTerm) ||
        (student.firstName || '').toLowerCase().includes(searchTerm) ||
        (student.lastName || '').toLowerCase().includes(searchTerm) ||
        (student.email || '').toLowerCase().includes(searchTerm)
    );
    
    displayStudents(filteredStudents);
}

async function refreshStudentData() {
    showMessage('Refreshing student data...', 'info');
    await loadStudentData();
    clearMessage();
}

async function exportStudentData() {
    try {
        const csvContent = generateCSVFromStudents(currentStudents);
        downloadCSV(csvContent, 'students_export.csv');
        showMessage('Student data exported successfully.', 'success');
    } catch (error) {
        showMessage('Error exporting data: ' + error.message, 'error');
    }
}

async function loadAnalytics() {
    console.log('🔄 Loading analytics data...');
    
    // Set loading state
    const elements = ['total-students', 'scans-today', 'unique-scans', 'success-rate'];
    elements.forEach(id => {
        const element = document.getElementById(id);
        if (element) element.textContent = 'Loading...';
    });
    
    try {
        console.log('📊 Fetching students data...');
        // Get total students
        const studentsSnapshot = await db.collection('students').get();
        const totalStudents = studentsSnapshot.size;
        console.log('📊 Total students:', totalStudents);
        document.getElementById('total-students').textContent = totalStudents;
        
        console.log('📊 Fetching scans data...');
        // Get scans data
        const today = new Date();
        const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        console.log('📊 Filtering scans from:', todayStart);
        
        const scansSnapshot = await db.collection('scans')
            .where('timestamp', '>=', todayStart.getTime())
            .get();
        
        const scansToday = scansSnapshot.size;
        console.log('📊 Scans today:', scansToday);
        document.getElementById('scans-today').textContent = scansToday;
        
        // Calculate unique students scanned
        const uniqueStudents = new Set(scansSnapshot.docs.map(doc => doc.data().code));
        const uniqueScansCount = uniqueStudents.size;
        console.log('📊 Unique students scanned:', uniqueScansCount);
        document.getElementById('unique-scans').textContent = uniqueScansCount;
        
        // Calculate success rate (assuming successful scans have student match)
        const successfulScans = scansSnapshot.docs.filter(doc => doc.data().verified === true);
        const successRate = scansToday > 0 ? Math.round((successfulScans.length / scansToday) * 100) : 0;
        console.log('📊 Success rate:', successRate + '%');
        document.getElementById('success-rate').textContent = successRate + '%';
        
        // Load recent activity
        await loadRecentActivity();
        
        console.log('✅ Analytics loaded successfully');
        
    } catch (error) {
        console.error('❌ Error loading analytics:', error);
        // Reset to error state
        elements.forEach(id => {
            const element = document.getElementById(id);
            if (element) element.textContent = 'Error';
        });
        showMessage('Failed to load analytics data: ' + error.message, 'error');
    }
}

async function loadRecentActivity() {
    try {
        const recentScans = await db.collection('scans')
            .limit(50)
            .get();
        
        // Sort by timestamp and take the most recent 10
        const sortedScans = recentScans.docs
            .map(doc => ({ id: doc.id, ...doc.data() }))
            .sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0))
            .slice(0, 10);
        
        const activityHTML = sortedScans.map(scan => {
            const timestamp = new Date(scan.timestamp);
            return `
                <div style="display: flex; justify-content: space-between; align-items: center; padding: 10px 0; border-bottom: 1px solid #e2e8f0;">
                    <div>
                        <strong>Student ID: ${scan.code}</strong>
                        <div style="color: #718096; font-size: 0.9rem;">${scan.verified ? '✅ Verified' : '❌ Not Found'}</div>
                    </div>
                    <div style="color: #718096; font-size: 0.9rem;">
                        ${timestamp.toLocaleString()}
                    </div>
                </div>
            `;
        }).join('');
        
        document.getElementById('recent-activity').innerHTML = activityHTML || 
            '<p style="color: #718096; text-align: center; padding: 20px;">No recent activity found.</p>';
        
    } catch (error) {
        console.error('Error loading recent activity:', error);
    }
}

async function updateAnalytics() {
    // Update system analytics in Firestore
    try {
        const studentsCount = await db.collection('students').get().then(snap => snap.size);
        
        await db.collection('analytics').doc('system').set({
            totalStudents: studentsCount,
            lastUpdated: firebase.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        
    } catch (error) {
        console.error('Error updating analytics:', error);
    }
}

// Student Image Functions
async function getStudentImageUrl(studentId) {
    // Check cache first
    if (studentImageCache.has(studentId)) {
        return studentImageCache.get(studentId);
    }
    
    try {
        // Try common image extensions
        const extensions = ['jpg', 'jpeg', 'png', 'webp'];
        
        for (const ext of extensions) {
            try {
                const imageRef = storage.ref(`student-photos/${studentId}.${ext}`);
                const url = await imageRef.getDownloadURL();
                // Cache the successful URL
                studentImageCache.set(studentId, url);
                return url;
            } catch (error) {
                // Continue to next extension if this one fails
                continue;
            }
        }
        
        // No image found, cache null to avoid repeated lookups
        studentImageCache.set(studentId, null);
        return null;
        
    } catch (error) {
        console.warn(`Error loading image for student ${studentId}:`, error);
        studentImageCache.set(studentId, null);
        return null;
    }
}

function createStudentImageElement(studentId, size = '40px') {
    const imgContainer = document.createElement('div');
    imgContainer.style.cssText = `
        width: ${size}; 
        height: ${size}; 
        border-radius: 50%; 
        overflow: hidden; 
        background: #f7fafc; 
        display: flex; 
        align-items: center; 
        justify-content: center;
        border: 2px solid #e2e8f0;
    `;
    
    // Create placeholder initially
    imgContainer.innerHTML = `
        <div style="color: #a0aec0; font-size: 12px; font-weight: 600;">
            ${studentId ? studentId.substring(0, 2).toUpperCase() : '??'}
        </div>
    `;
    
    // Load actual image asynchronously
    if (studentId) {
        getStudentImageUrl(studentId).then(imageUrl => {
            if (imageUrl) {
                imgContainer.innerHTML = `
                    <img src="${imageUrl}" 
                         alt="Student ${studentId}" 
                         style="width: 100%; height: 100%; object-fit: cover;"
                         onerror="this.style.display='none'">
                `;
            }
        });
    }
    
    return imgContainer;
}

// Photo Upload Functions
function showPhotoUploadForm() {
    console.log('showPhotoUploadForm called');
    
    // Check if storage is available
    if (!storage) {
        showMessage('Firebase Storage is not initialized. Please refresh the page.', 'error');
        return;
    }
    const content = `
        <div style="padding: 20px;">
            <h3 style="margin-bottom: 20px;">Bulk Student Photo Upload</h3>
            <p style="color: #4a5568; margin-bottom: 20px;">
                Upload multiple student photos at once. Images should be named with the student ID 
                (e.g., "AB1234567.jpg", "XY9876543.png"). Supported formats: JPG, PNG, WEBP.
            </p>
            
            <div id="photo-upload-area" 
                 style="border: 3px dashed #667eea; border-radius: 15px; padding: 40px; text-align: center; 
                        background: #f8f9ff; margin-bottom: 20px; cursor: pointer;"
                 onclick="document.getElementById('photo-files').click()"
                 ondrop="handlePhotoDrop(event)" 
                 ondragover="handlePhotoDragOver(event)"
                 ondragleave="handlePhotoDragLeave(event)">
                <svg width="48" height="48" style="color: #667eea; margin-bottom: 16px;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
                    <circle cx="8.5" cy="8.5" r="1.5"/>
                    <polyline points="21,15 16,10 5,21"/>
                </svg>
                <p style="margin: 0; color: #4a5568; font-size: 1.1rem;">
                    <strong>Drop photos here or click to select</strong><br>
                    <span style="font-size: 0.9rem; color: #718096;">
                        Multiple files supported • Max 5MB per file
                    </span>
                </p>
            </div>
            
            <input type="file" id="photo-files" multiple accept="image/*" style="display: none;" onchange="handlePhotoFiles(this.files)">
            
            <div id="photo-upload-progress" style="display: none; margin-top: 20px;">
                <h4>Upload Progress</h4>
                <div id="photo-progress-list"></div>
                <div style="margin-top: 15px;">
                    <button class="btn btn-success" onclick="startPhotoUpload()" id="start-upload-btn">
                        Start Upload
                    </button>
                    <button class="btn btn-secondary" onclick="clearPhotoQueue()" style="margin-left: 10px;">
                        Clear Queue
                    </button>
                </div>
            </div>
        </div>
    `;
    
    showModal('Upload Student Photos', content);
}

// Make sure all photo functions are globally accessible
window.showPhotoUploadForm = showPhotoUploadForm;
window.handlePhotoDrop = handlePhotoDrop;
window.handlePhotoDragOver = handlePhotoDragOver;
window.handlePhotoDragLeave = handlePhotoDragLeave;
window.handlePhotoFiles = handlePhotoFiles;
window.startPhotoUpload = startPhotoUpload;
window.clearPhotoQueue = clearPhotoQueue;

let photoUploadQueue = [];

function handlePhotoDragOver(event) {
    event.preventDefault();
    event.currentTarget.style.borderColor = '#5a67d8';
    event.currentTarget.style.background = '#f0f4ff';
}

function handlePhotoDragLeave(event) {
    event.currentTarget.style.borderColor = '#667eea';
    event.currentTarget.style.background = '#f8f9ff';
}

function handlePhotoDrop(event) {
    event.preventDefault();
    const uploadArea = event.currentTarget;
    uploadArea.style.borderColor = '#667eea';
    uploadArea.style.background = '#f8f9ff';
    
    const files = event.dataTransfer.files;
    handlePhotoFiles(files);
}

function handlePhotoFiles(files) {
    photoUploadQueue = [];
    const progressSection = document.getElementById('photo-upload-progress');
    const progressList = document.getElementById('photo-progress-list');
    
    if (files.length === 0) {
        progressSection.style.display = 'none';
        return;
    }
    
    // Validate and queue files
    let validFiles = 0;
    Array.from(files).forEach(file => {
        const fileName = file.name.toLowerCase();
        const fileExtension = fileName.split('.').pop();
        const studentId = fileName.replace(/\.(jpg|jpeg|png|webp)$/, '').toUpperCase();
        
        // Validate file type
        if (!['jpg', 'jpeg', 'png', 'webp'].includes(fileExtension)) {
            console.warn(`Skipping ${file.name}: unsupported file type`);
            return;
        }
        
        // Validate file size (5MB max)
        if (file.size > 5 * 1024 * 1024) {
            console.warn(`Skipping ${file.name}: file too large (max 5MB)`);
            return;
        }
        
        // Validate student ID format (2 letters + 7 numbers)
        const idPattern = /^[A-Za-z]{2}\d{7}$/;
        if (!idPattern.test(studentId)) {
            console.warn(`Skipping ${file.name}: invalid student ID format (expected: 2 letters + 7 numbers)`);
            return;
        }
        
        photoUploadQueue.push({
            file: file,
            studentId: studentId,
            fileName: file.name,
            size: file.size,
            status: 'queued'
        });
        validFiles++;
    });
    
    // Display queue
    progressList.innerHTML = photoUploadQueue.map((item, index) => `
        <div id="photo-item-${index}" style="display: flex; justify-content: space-between; align-items: center; padding: 10px; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px;">
            <div>
                <strong>${item.studentId}</strong> 
                <span style="color: #718096;">(${formatFileSize(item.size)})</span>
            </div>
            <div id="photo-status-${index}" style="color: #718096;">Queued</div>
        </div>
    `).join('');
    
    progressSection.style.display = validFiles > 0 ? 'block' : 'none';
    
    if (validFiles === 0) {
        showMessage('No valid photo files found. Please check file names and formats.', 'error');
    } else {
        showMessage(`${validFiles} photos queued for upload.`, 'info');
    }
}

async function startPhotoUpload() {
    if (photoUploadQueue.length === 0) {
        showMessage('No photos to upload.', 'error');
        return;
    }
    
    const startBtn = document.getElementById('start-upload-btn');
    startBtn.disabled = true;
    startBtn.textContent = 'Uploading...';
    
    let successful = 0;
    let failed = 0;
    
    for (let i = 0; i < photoUploadQueue.length; i++) {
        const item = photoUploadQueue[i];
        const statusElement = document.getElementById(`photo-status-${i}`);
        
        try {
            statusElement.textContent = 'Uploading...';
            statusElement.style.color = '#3182ce';
            
            // Upload to Firebase Storage
            const storageRef = storage.ref(`student-photos/${item.studentId}.${item.file.name.split('.').pop()}`);
            await storageRef.put(item.file);
            
            // Update cache to include new image
            const downloadUrl = await storageRef.getDownloadURL();
            studentImageCache.set(item.studentId, downloadUrl);
            
            statusElement.textContent = '✅ Uploaded';
            statusElement.style.color = '#22543d';
            successful++;
            
        } catch (error) {
            console.error(`Failed to upload ${item.fileName}:`, error);
            statusElement.textContent = '❌ Failed';
            statusElement.style.color = '#e53e3e';
            failed++;
        }
    }
    
    startBtn.disabled = false;
    startBtn.textContent = 'Start Upload';
    
    showMessage(`Upload complete: ${successful} successful, ${failed} failed.`, successful > 0 ? 'success' : 'error');
    
    // Refresh student display to show new photos
    if (successful > 0) {
        displayStudents(currentStudents);
    }
}

function clearPhotoQueue() {
    photoUploadQueue = [];
    document.getElementById('photo-upload-progress').style.display = 'none';
    document.getElementById('photo-files').value = '';
}

// Utility functions
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function showMessage(message, type) {
    const messageDiv = document.getElementById('status-message');
    messageDiv.textContent = message;
    messageDiv.className = `status-message status-${type}`;
    messageDiv.classList.remove('hidden');
    
    if (type === 'success' || type === 'info') {
        setTimeout(() => {
            clearMessage();
        }, 5000);
    }
}

function clearMessage() {
    const messageDiv = document.getElementById('status-message');
    messageDiv.classList.add('hidden');
}

function generateCSVFromStudents(students) {
    const headers = ['Student ID', 'First Name', 'Last Name', 'Email', 'Program', 'Year'];
    const csvRows = [headers.join(',')];
    
    students.forEach(student => {
        const row = [
            student.studentId || '',
            student.firstName || '',
            student.lastName || '',
            student.email || '',
            student.program || '',
            student.year || ''
        ];
        csvRows.push(row.map(field => `"${field}"`).join(','));
    });
    
    return csvRows.join('\n');
}

function downloadCSV(csvContent, filename) {
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    
    if (link.download !== undefined) {
        const url = URL.createObjectURL(blob);
        link.setAttribute('href', url);
        link.setAttribute('download', filename);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
}

// Event Management Functions
async function loadEvents() {
    try {
        const eventsSnapshot = await db.collection('events')
            .get(); // Remove orderBy to avoid index issues
        
        const events = eventsSnapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data()
        }))
        // Attendance events only: department scan lists (groupId set, e.g.
        // Admissions) never appear here — they live in the Scan Lists tab,
        // scoped to their own group. Keeps SONIS exports and student
        // attendance strictly separated from prospect scanning.
        .filter(event => !event.groupId);

        // Chronological: earliest event date first, matching the iOS app.
        // Events without a date sort to the end by creation time.
        events.sort((a, b) => {
            const dateA = tsToMillis(a.date) || (8.64e15 + tsToMillis(a.createdAt));
            const dateB = tsToMillis(b.date) || (8.64e15 + tsToMillis(b.createdAt));
            return dateA - dateB;
        });
        
        // Store original events for filtering
        window.originalEvents = events;
        
        // Populate the year filter dropdown
        populateYearFilter(events);
        
        // Apply initial filters (defaults to active events)
        applyEventFilters();
        
    } catch (error) {
        console.error('Error loading events:', error);
        document.getElementById('events-list').innerHTML = `
            <div style="background: #fed7d7; padding: 30px; text-align: center; border-radius: 15px; color: #742a2a;">
                Error loading events: ${error.message}
            </div>
        `;
    }
}

function displayEvents(events) {
    const eventsList = document.getElementById('events-list');
    
    if (events.length === 0) {
        eventsList.innerHTML = `
            <div style="background: #f7fafc; padding: 40px; text-align: center; border-radius: 15px; color: #718096;">
                No events found with current filters.
            </div>
        `;
        return;
    }
    
    // Store events globally for filtering
    window.allEvents = events;
    
    const eventsHTML = events.map(event => {
        const createdDate = tsToMillis(event.createdAt) ? new Date(tsToMillis(event.createdAt)).toLocaleDateString() : 'Unknown';
        const eventDate = tsToMillis(event.date) ? new Date(tsToMillis(event.date)).toLocaleDateString(undefined, { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC' }) : 'No date';
        const isActive = event.isActive ? '✅ Active' : '⏸️ Inactive';
        
        return `
            <div class="event-card" style="background: white; border: 2px solid #e2e8f0; border-radius: 15px; padding: 20px; margin-bottom: 15px;">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <div style="flex: 1;">
                        <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
                            <h3 style="color: #2d3748; margin: 0;">Event #${event.eventNumber}: ${event.name}</h3>
                            ${event.isCCC ? `<span style="background: #bee3f8; color: #2a4365; padding: 4px 12px; border-radius: 20px; font-size: 0.85rem; font-weight: 600;">PS #${event.eventNumber} + CCC #${event.cccEventId}</span>` : ''}
                            <span style="background: ${event.isActive ? '#c6f6d5' : '#fed7d7'}; color: ${event.isActive ? '#22543d' : '#742a2a'}; padding: 4px 12px; border-radius: 20px; font-size: 0.85rem; font-weight: 600;">${isActive}</span>
                        </div>
                        ${event.description ? `<p style="color: #718096; margin: 5px 0; font-size: 0.95rem;">${event.description}</p>` : ''}
                        <div style="color: #4a5568; font-size: 0.95rem; font-weight: 600;">
                            📅 ${eventDate}
                            <span style="font-weight: 400; color: #a0aec0; font-size: 0.8rem; margin-left: 10px;">created ${createdDate}</span>
                        </div>
                    </div>
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <select id="action-${event.id}" class="btn btn-secondary" style="padding: 8px 12px; font-size: 0.9rem; cursor: pointer;">
                            <option value="">Select Action...</option>
                            <option value="view">View Scans</option>
                            <option value="export-text-new">${event.isCCC ? 'Export SIS Files (NEW since last export, zip)' : 'Export Text (NEW since last export)'}</option>
                            <option value="export-text">${event.isCCC ? 'Export SIS Files (Add ALL, zip)' : 'Export Text (Add ALL)'}</option>
                            <option value="export-text-remove">${event.isCCC ? 'Export SIS Files (Removal, zip)' : 'Export Text (Removal)'}</option>
                            ${event.isCCC ? `
                            <option value="export-text-ps">Export PS File Only (Add)</option>
                            <option value="export-text-ccc">Export CCC File Only (Add)</option>
                            <option value="export-text-ps-remove">Export PS File Only (Removal)</option>
                            <option value="export-text-ccc-remove">Export CCC File Only (Removal)</option>` : ''}
                            <option value="export-xlsx">Export XLSX</option>
                            <option value="export-errors">Export Errors</option>
                            <option value="edit-id">Edit Event ID</option>
                            <option value="toggle-status">${event.isActive ? 'Deactivate' : 'Activate'} Event</option>
                            <option value="delete">Delete Event</option>
                        </select>
                        <button class="btn btn-primary" onclick="executeEventAction('${event.id}', '${event.eventNumber}', '${event.name.replace(/'/g, "\\'")}', ${event.isActive})" 
                                style="padding: 8px 16px; font-size: 0.9rem;">
                            Go
                        </button>
                    </div>
                </div>
            </div>
        `;
    }).join('');
    
    eventsList.innerHTML = eventsHTML;
}

function executeEventAction(eventId, eventNumber, eventName, isActive) {
    const selectElement = document.getElementById(`action-${eventId}`);
    const action = selectElement.value;
    
    if (!action) {
        showMessage('Please select an action first.', 'error');
        return;
    }
    
    // Convert string parameters to proper types
    const eventNum = parseInt(eventNumber);
    const active = isActive === 'true' || isActive === true;
    
    switch(action) {
        case 'view':
            console.log('Executing view action for event:', eventId);
            viewDetailedScans(eventId);
            break;
        case 'export-text':
            exportEventText(eventId);
            break;
        case 'export-text-new':
            exportEventText(eventId, { newOnly: true });
            break;
        case 'export-text-remove':
            exportEventText(eventId, { flag: '0' });
            break;
        case 'export-text-ps':
            exportEventText(eventId, { only: 'ps' });
            break;
        case 'export-text-ccc':
            exportEventText(eventId, { only: 'ccc' });
            break;
        case 'export-text-ps-remove':
            exportEventText(eventId, { only: 'ps', flag: '0' });
            break;
        case 'export-text-ccc-remove':
            exportEventText(eventId, { only: 'ccc', flag: '0' });
            break;
        case 'export-xlsx':
            exportEventXLSX(eventId);
            break;
        case 'export-errors':
            exportEventErrors(eventId);
            break;
        case 'edit-id':
            editEventNumber(eventId, eventNum);
            break;
        case 'toggle-status':
            toggleEventStatus(eventId, !active);
            break;
        case 'delete':
            deleteEvent(eventId, eventName);
            break;
        default:
            showMessage('Invalid action selected.', 'error');
    }
    
    // Reset the dropdown
    selectElement.value = '';
}

function applyEventFilters() {
    const searchTerm = document.getElementById('event-search').value.toLowerCase();
    const yearFilter = document.getElementById('event-year-filter').value;
    const statusFilter = document.getElementById('event-status-filter').value;
    
    if (!window.originalEvents || window.originalEvents.length === 0) {
        return;
    }
    
    let filteredEvents = window.originalEvents.filter(event => {
        // Text search filter
        const matchesSearch = !searchTerm || 
            event.name.toLowerCase().includes(searchTerm) ||
            event.eventNumber.toString().includes(searchTerm) ||
            (event.description && event.description.toLowerCase().includes(searchTerm));
        
        // Year filter
        const eventYear = tsToMillis(event.createdAt) ? new Date(tsToMillis(event.createdAt)).getFullYear().toString() : null;
        const matchesYear = yearFilter === 'all' || eventYear === yearFilter;
        
        // Status filter
        let matchesStatus = false;
        if (statusFilter === 'all') {
            matchesStatus = true;
        } else if (statusFilter === 'active') {
            matchesStatus = event.isActive === true;
        } else if (statusFilter === 'inactive') {
            matchesStatus = event.isActive === false;
        }
        
        return matchesSearch && matchesYear && matchesStatus;
    });
    
    displayEvents(filteredEvents);
}

function populateYearFilter(events) {
    const yearFilter = document.getElementById('event-year-filter');
    const years = new Set();
    
    events.forEach(event => {
        if (event.createdAt) {
            const year = new Date(tsToMillis(event.createdAt) || Date.now()).getFullYear();
            years.add(year);
        }
    });
    
    // Clear existing options except "All Years"
    yearFilter.innerHTML = '<option value="all">All Years</option>';
    
    // Add years in descending order
    Array.from(years).sort((a, b) => b - a).forEach(year => {
        const option = document.createElement('option');
        option.value = year.toString();
        option.textContent = year.toString();
        yearFilter.appendChild(option);
    });
}

function showNewEventForm() {
    document.getElementById('new-event-form').classList.remove('hidden');
}

function hideNewEventForm() {
    document.getElementById('new-event-form').classList.add('hidden');
    document.getElementById('event-number').value = '';
    document.getElementById('event-name').value = '';
    document.getElementById('event-description').value = '';
    document.getElementById('event-is-ccc').checked = false;
    document.getElementById('event-ccc-id').value = '';
    document.getElementById('ccc-id-row').style.display = 'none';
}

async function createNewEvent() {
    const eventNumber = parseInt(document.getElementById('event-number').value);
    const eventName = document.getElementById('event-name').value.trim();
    const eventDescription = document.getElementById('event-description').value.trim();
    const isCCC = document.getElementById('event-is-ccc').checked;
    const cccEventId = parseInt(document.getElementById('event-ccc-id').value);

    if (!eventNumber || !eventName) {
        showMessage('Please provide both event number and name.', 'error');
        return;
    }
    if (isCCC && !cccEventId) {
        showMessage('CCC events need a CCC Event ID (the Event Number is used as the PS ID).', 'error');
        return;
    }
    if (isCCC && cccEventId === eventNumber) {
        showMessage('The CCC Event ID must differ from the Event Number (PS ID).', 'error');
        return;
    }
    
    const createBtn = document.getElementById('create-event-btn');
    createBtn.innerHTML = '<span class="loading"></span>Creating...';
    createBtn.disabled = true;
    
    try {
        // Check if event number already exists
        const existingEvent = await db.collection('events')
            .where('eventNumber', '==', eventNumber)
            .get();
        
        if (!existingEvent.empty) {
            showMessage(`Event number ${eventNumber} already exists. Please use a different number.`, 'error');
            createBtn.innerHTML = 'Create Event';
            createBtn.disabled = false;
            return;
        }
        
        const eventDoc = {
            eventNumber: eventNumber,
            name: eventName,
            description: eventDescription,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            isActive: true,
            exportFormat: 'TEXT_DELIMITED',
            isCCC: isCCC,
            cccEventId: isCCC ? cccEventId : null
        };
        
        await db.collection('events').add(eventDoc);
        
        showMessage(`Event "${eventName}" created successfully!`, 'success');
        hideNewEventForm();
        loadEvents();
        
    } catch (error) {
        console.error('Error creating event:', error);
        showMessage('Error creating event: ' + error.message, 'error');
    } finally {
        createBtn.innerHTML = 'Create Event';
        createBtn.disabled = false;
    }
}

async function toggleEventStatus(eventId, newStatus) {
    try {
        await db.collection('events').doc(eventId).update({
            isActive: newStatus
        });
        
        showMessage(`Event ${newStatus ? 'activated' : 'deactivated'} successfully!`, 'success');
        loadEvents();
        
    } catch (error) {
        console.error('Error updating event status:', error);
        showMessage('Error updating event: ' + error.message, 'error');
    }
}

async function viewEventReport(eventId) {
    try {
        showMessage('Loading event report...', 'info');
        
        // Get event details
        const eventDoc = await db.collection('events').doc(eventId).get();
        if (!eventDoc.exists) {
            showMessage('Event not found.', 'error');
            return;
        }
        
        const event = eventDoc.data();
        
        // Get scans from BOTH structures using EVENT DOCUMENT ID (not event number)
        const [flatScansSnapshot, nestedScansSnapshot] = await Promise.all([
            // Flat structure (admin portal + new Flutter web app) - use eventId (document ID)
            db.collection('scans')
                .where('listId', '==', eventId)
                .get(),
            // Nested structure (Android app) - use EVENT DOCUMENT ID as listId
            db.collection('lists').doc(eventId)
                .collection('scans')
                .get()
        ]);
        
        // Combine scans from both sources, avoiding duplicates by ID
        const allScans = new Map();
        
        // Add flat structure scans
        flatScansSnapshot.docs.forEach(doc => {
            const scanData = doc.data();
            allScans.set(doc.id, scanData);
        });
        
        // Add nested structure scans (Android app data)
        nestedScansSnapshot.docs.forEach(doc => {
            const scanData = doc.data();
            // Convert Android app format to admin portal format
            const convertedScan = {
                code: scanData.code,
                timestamp: scanData.timestamp ? new Date(scanData.timestamp).getTime() : Date.now(),
                listId: eventId,
                deviceId: scanData.deviceId || '',
                verified: scanData.processed || false,
                symbology: scanData.symbology || '',
                studentId: scanData.studentId || '',
                firstName: '',
                lastName: '',
                email: ''
            };
            allScans.set(doc.id, convertedScan);
        });
        
        const scans = Array.from(allScans.values());
        
        // Generate report HTML
        const reportHTML = `
            <h3>Event Report: ${event.name} (#${event.eventNumber})</h3>
            <div style="margin: 20px 0;">
                <strong>Total Scans:</strong> ${scans.length}<br>
                <strong>Verified Students:</strong> ${scans.filter(s => s.verified).length}<br>
                <strong>Unverified Scans:</strong> ${scans.filter(s => !s.verified).length}<br>
                <strong>Sources:</strong> Flat: ${flatScansSnapshot.size}, Nested: ${nestedScansSnapshot.size}
            </div>
            <div style="max-height: 300px; overflow-y: auto;">
                <table class="preview-table">
                    <thead>
                        <tr>
                            <th>Student ID</th>
                            <th>Name</th>
                            <th>Time Scanned</th>
                            <th>Status</th>
                            <th>Source</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${scans.map(scan => `
                            <tr>
                                <td>${scan.code}</td>
                                <td>${scan.firstName || ''} ${scan.lastName || ''}</td>
                                <td>${new Date(scan.timestamp).toLocaleString()}</td>
                                <td>${scan.verified ? '✅ Verified' : '❌ Not Found'}</td>
                                <td>${flatScansSnapshot.docs.find(d => d.data().code === scan.code) ? 'Web' : 'Android'}</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        `;
        
        // You could open this in a modal or new window
        // For now, we'll just show a success message
        showMessage(`Report generated: ${scans.length} total scans for event "${event.name}" (${flatScansSnapshot.size} web + ${nestedScansSnapshot.size} android)`, 'success');
        
    } catch (error) {
        console.error('Error generating event report:', error);
        showMessage('Error generating report: ' + error.message, 'error');
    }
}

// SONIS fixed-width attendance export.
//
// Line format (must match SONIS exactly): "{sisEventId} {studentId}{flag}"
//   e.g. "491 AL13777291" = event 491, student AL1377729, flag 1 (add).
// flag '1' adds the attendance record in SONIS; flag '0' removes it (for
// duplicate uploads or event-setup mistakes).
//
// Cross-Cultural Competency events carry two SIS ids — the eventNumber acts
// as the Professionalism Series (PS) id and cccEventId as the CCC id — and
// export as a zip holding one file per id, or a single file via opts.only.
async function exportEventText(eventId, opts = {}) {
    const flag = opts.flag === '0' ? '0' : '1';
    try {
        showMessage('Preparing text export...', 'info');
        
        // Get event details
        const eventDoc = await db.collection('events').doc(eventId).get();
        if (!eventDoc.exists) {
            showMessage('Event not found.', 'error');
            return;
        }
        
        const event = eventDoc.data();
        
        // Get scans from BOTH structures
        const [flatScansSnapshot, nestedScansSnapshot] = await Promise.all([
            // Flat structure
            db.collection('scans')
                .where('listId', '==', eventId)
                .get(),
            // Nested structure (Android app)
            db.collection('lists').doc(eventId)
                .collection('scans')
                .get()
        ]);
        
        // Combine and deduplicate scans by student ID
        // Only include VALID scans (verified students with correct ID format)
        const uniqueStudentIds = new Set();
        let rejectedCount = 0;
        let invalidFormatCount = 0;
        let unverifiedCount = 0;
        
        // Regex pattern for valid student ID: 2 letters followed by 7 numbers
        const validIdPattern = /^[A-Za-z]{2}\d{7}$/;
        
        // Add flat structure scans - only verified ones with valid format
        flatScansSnapshot.docs.forEach(doc => {
            const scan = doc.data();
            const cleanId = scan.code.replace(/\s/g, '').toUpperCase();
            
            // Check format first
            if (!validIdPattern.test(cleanId)) {
                invalidFormatCount++;
                console.log(`Rejected invalid format: ${cleanId}`);
                rejectedCount++;
                return;
            }
            
            // Then check verification
            if (scan.verified !== true) {
                unverifiedCount++;
                console.log(`Rejected unverified: ${cleanId}`);
                rejectedCount++;
                return;
            }
            
            // Only add if both checks pass
            uniqueStudentIds.add(cleanId);
        });
        
        // Add nested structure scans - only verified ones with valid format
        nestedScansSnapshot.docs.forEach(doc => {
            const scan = doc.data();
            const cleanId = scan.code.replace(/\s/g, '').toUpperCase();
            
            // Check format first
            if (!validIdPattern.test(cleanId)) {
                invalidFormatCount++;
                console.log(`Rejected invalid format (Android): ${cleanId}`);
                rejectedCount++;
                return;
            }
            
            // Then check verification (Android uses processed field)
            if (scan.processed !== true) {
                unverifiedCount++;
                console.log(`Rejected unprocessed (Android): ${cleanId}`);
                rejectedCount++;
                return;
            }
            
            // Only add if both checks pass
            uniqueStudentIds.add(cleanId);
        });
        
        // Convert to sorted array and generate text content
        const sortedIds = Array.from(uniqueStudentIds).sort();

        // The export ledger records every batch sent to SONIS, so "new only"
        // exports can exclude students whose attendance is already posted —
        // re-running an export can never double-post attendance.
        const ledgerSnapshot = await db.collection('sonis_exports')
            .where('eventId', '==', eventId).get();
        const batches = ledgerSnapshot.docs.map(d => d.data())
            .sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)));
        const exportedSetFor = (sisId) => {
            const set = new Set();
            for (const b of batches) {
                if (String(b.sisId) !== String(sisId)) continue;
                for (const sid of (b.studentIds || [])) {
                    if (b.flag === '0') set.delete(sid); else set.add(sid);
                }
            }
            return set;
        };
        const idsFor = (sisId) => {
            if (!opts.newOnly) return sortedIds;
            const already = exportedSetFor(sisId);
            return sortedIds.filter(id => !already.has(id));
        };
        const recordBatch = async (sisId, ids, fname) => {
            try {
                await db.collection('sonis_exports').add({
                    eventId: eventId,
                    sisId: sisId,
                    flag: flag,
                    studentIds: ids,
                    count: ids.length,
                    filename: fname,
                    newOnly: !!opts.newOnly,
                    exportedAt: new Date().toISOString(),
                });
            } catch (e) {
                console.error('Failed to record export batch:', e);
                showMessage('Warning: export downloaded but the ledger update failed. "New only" exports may over-include until the next successful export.', 'error');
            }
        };

        // CRLF line endings and a trailing terminator match the SONIS sample
        // file byte-for-byte (verified against a hexdump of a real upload).
        const buildContent = (sisId, ids) => ids
            .map(studentId => `${sisId} ${studentId}${flag}`)
            .join('\r\n') + '\r\n';

        const today = new Date();
        const dateString = `${(today.getMonth() + 1).toString().padStart(2, '0')}${today.getDate().toString().padStart(2, '0')}${today.getFullYear().toString().substr(2)}`;
        const suffix = flag === '0' ? '_REMOVE' : '';

        const newTag = opts.newOnly ? '_NEW' : '';
        let filename;
        if (event.isCCC && event.cccEventId && !opts.only) {
            // Both SIS files, bundled so neither upload gets forgotten.
            const psIds = idsFor(event.eventNumber);
            const cccIds = idsFor(event.cccEventId);
            if (psIds.length === 0 && cccIds.length === 0) {
                showMessage('Nothing new to export: every scanned student is already in SONIS for both IDs.', 'info');
                return;
            }
            const psName = `Event_${event.eventNumber}_PS_${dateString}${newTag}${suffix}.txt`;
            const cccName = `Event_${event.cccEventId}_CCC_${dateString}${newTag}${suffix}.txt`;
            const zip = new JSZip();
            if (psIds.length) zip.file(psName, buildContent(event.eventNumber, psIds));
            if (cccIds.length) zip.file(cccName, buildContent(event.cccEventId, cccIds));
            filename = `Event_${event.eventNumber}_PS_CCC_${dateString}${newTag}${suffix}.zip`;
            const blob = await zip.generateAsync({ type: 'blob' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = filename;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
            if (psIds.length) await recordBatch(event.eventNumber, psIds, psName);
            if (cccIds.length) await recordBatch(event.cccEventId, cccIds, cccName);
        } else if (opts.only === 'ccc') {
            if (!event.isCCC || !event.cccEventId) {
                showMessage('This event has no CCC Event ID configured.', 'error');
                return;
            }
            const ids = idsFor(event.cccEventId);
            if (ids.length === 0) {
                showMessage('Nothing new to export for the CC ID.', 'info');
                return;
            }
            filename = `Event_${event.cccEventId}_CCC_${dateString}${newTag}${suffix}.txt`;
            downloadTextFile(buildContent(event.cccEventId, ids), filename);
            await recordBatch(event.cccEventId, ids, filename);
        } else {
            const tag = (event.isCCC && opts.only === 'ps') ? '_PS' : '';
            const ids = idsFor(event.eventNumber);
            if (ids.length === 0) {
                showMessage('Nothing new to export: every scanned student is already in SONIS.', 'info');
                return;
            }
            filename = `Event_${event.eventNumber}${tag}_${dateString}${newTag}${suffix}.txt`;
            downloadTextFile(buildContent(event.eventNumber, ids), filename);
            await recordBatch(event.eventNumber, ids, filename);
        }
        
        const totalScans = flatScansSnapshot.size + nestedScansSnapshot.size;
        const duplicatesAndErrors = totalScans - sortedIds.length;
        showMessage(
            `Exported ${sortedIds.length} valid student IDs to ${filename}. ` +
            `Rejected ${rejectedCount} scans (${invalidFormatCount} invalid format, ${unverifiedCount} unverified). ` +
            `Total scans processed: ${totalScans}`, 
            'success'
        );
        
    } catch (error) {
        console.error('Error exporting text data:', error);
        showMessage('Error exporting data: ' + error.message, 'error');
    }
}

async function exportEventXLSX(eventId) {
    try {
        showMessage('Preparing XLSX export...', 'info');
        
        // Get event details
        const eventDoc = await db.collection('events').doc(eventId).get();
        if (!eventDoc.exists) {
            showMessage('Event not found.', 'error');
            return;
        }
        
        const event = eventDoc.data();
        
        // Get scans for this event
        const scansSnapshot = await db.collection('scans')
            .where('eventId', '==', eventId)
            .get();
        
        const scans = scansSnapshot.docs.map(doc => doc.data());
        
        // Create worksheet data
        const worksheetData = [
            ['Event', 'Student ID', 'First Name', 'Last Name', 'Email', 'Program', 'Year', 'Scanned At', 'Device', 'Status']
        ];
        
        scans.forEach(scan => {
            worksheetData.push([
                event.name,
                scan.code,
                scan.firstName || '',
                scan.lastName || '',
                scan.email || '',
                scan.program || '',
                scan.year || '',
                new Date(scan.timestamp).toLocaleString(),
                scan.deviceId,
                scan.verified ? 'Verified' : 'Unverified'
            ]);
        });
        
        // Create workbook and worksheet
        const wb = XLSX.utils.book_new();
        const ws = XLSX.utils.aoa_to_sheet(worksheetData);
        XLSX.utils.book_append_sheet(wb, ws, 'Event Report');
        
        // Download the file
        const today = new Date();
        const dateString = `${(today.getMonth() + 1).toString().padStart(2, '0')}${today.getDate().toString().padStart(2, '0')}${today.getFullYear().toString().substr(2)}`;
        const filename = `Event_${event.eventNumber}_Report_${dateString}.xlsx`;
        
        XLSX.writeFile(wb, filename);
        showMessage(`Exported ${scans.length} scans to ${filename}`, 'success');
        
    } catch (error) {
        console.error('Error exporting XLSX:', error);
        showMessage('Error exporting XLSX: ' + error.message, 'error');
    }
}

async function exportEventErrors(eventId) {
    try {
        showMessage('Preparing error export...', 'info');
        
        // Get event details
        const eventDoc = await db.collection('events').doc(eventId).get();
        if (!eventDoc.exists) {
            showMessage('Event not found.', 'error');
            return;
        }
        
        const event = eventDoc.data();
        
        // Get scans from BOTH structures
        const [flatScansSnapshot, nestedScansSnapshot] = await Promise.all([
            // Flat structure
            db.collection('scans')
                .where('listId', '==', eventId)
                .get(),
            // Nested structure (Android app)
            db.collection('lists').doc(eventId)
                .collection('scans')
                .get()
        ]);
        
        // Regex pattern for valid student ID: 2 letters followed by 7 numbers
        const validIdPattern = /^[A-Za-z]{2}\d{7}$/;
        
        // Collect all error scans
        const errorScans = [];
        
        // Process flat structure scans
        flatScansSnapshot.docs.forEach(doc => {
            const scan = doc.data();
            const cleanId = scan.code.replace(/\s/g, '').toUpperCase();
            let errorReason = null;
            
            if (!validIdPattern.test(cleanId)) {
                errorReason = 'Invalid ID Format (expected: 2 letters + 7 numbers)';
            } else if (scan.verified === false) {
                errorReason = 'Student Not Found in Database';
            }
            
            if (errorReason) {
                errorScans.push({
                    code: scan.code,
                    reason: errorReason,
                    source: 'Web Portal'
                });
            }
        });
        
        // Process nested structure scans
        nestedScansSnapshot.docs.forEach(doc => {
            const scan = doc.data();
            const cleanId = scan.code.replace(/\s/g, '').toUpperCase();
            let errorReason = null;
            
            if (!validIdPattern.test(cleanId)) {
                errorReason = 'Invalid ID Format (expected: 2 letters + 7 numbers)';
            } else if (scan.processed === false || scan.verified === false) {
                errorReason = 'Student Not Found in Database';
            }
            
            if (errorReason) {
                errorScans.push({
                    code: scan.code,
                    reason: errorReason,
                    source: 'Android App'
                });
            }
        });
        
        if (errorScans.length === 0) {
            showMessage('No errors found for this event.', 'info');
            return;
        }
        
        // Generate error content with more details
        const errorContent = errorScans.map(error => {
            return `${error.code} - ${error.reason} (Source: ${error.source})`;
        }).join('\n');
        
        const today = new Date();
        const dateString = `${(today.getMonth() + 1).toString().padStart(2, '0')}${today.getDate().toString().padStart(2, '0')}${today.getFullYear().toString().substr(2)}`;
        const filename = `Event_${event.eventNumber}_Errors_${dateString}.txt`;
        
        downloadTextFile(errorContent, filename);
        showMessage(`Exported ${errorScans.length} error records to ${filename}`, 'success');
        
    } catch (error) {
        console.error('Error exporting errors:', error);
        showMessage('Error exporting errors: ' + error.message, 'error');
    }
}

function downloadTextFile(content, filename) {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8;' });
    const link = document.createElement('a');
    
    if (link.download !== undefined) {
        const url = URL.createObjectURL(blob);
        link.setAttribute('href', url);
        link.setAttribute('download', filename);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
}

function downloadTemplate() {
    // Create template CSV with headers only (no sample data)
    const templateContent = `StudentID,FirstName,LastName,Email`;
    
    const blob = new Blob([templateContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    
    if (link.download !== undefined) {
        const url = URL.createObjectURL(blob);
        link.setAttribute('href', url);
        link.setAttribute('download', 'student_upload_template.csv');
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
    
    showMessage('Template CSV downloaded. Fill in the required fields: StudentID, FirstName, LastName, and Email.', 'success');
}

async function clearAllStudentData() {
    try {
        // First, check if there's any data to clear
        const studentsSnapshot = await db.collection('students').get();
        
        if (studentsSnapshot.empty) {
            showMessage('No student data to clear.', 'info');
            return;
        }
        
        const studentCount = studentsSnapshot.size;
        
        // Show warning and backup prompt
        const backupConfirmed = confirm(
            `⚠️ WARNING: You are about to delete ALL ${studentCount} student records!\n\n` +
            `Would you like to create an archive backup first?\n\n` +
            `Click OK to create a backup before clearing.\n` +
            `Click Cancel to abort this operation.`
        );
        
        if (!backupConfirmed) {
            showMessage('Clear operation cancelled.', 'info');
            return;
        }
        
        const clearBtn = document.getElementById('clear-data-btn');
        clearBtn.innerHTML = '<span class="loading"></span>Creating Backup...';
        clearBtn.disabled = true;
        
        // Create automatic backup before clearing
        showMessage('Creating safety backup...', 'info');
        
        const backupId = `pre_clear_backup_${Date.now()}`;
        const backupData = {
            id: backupId,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            timestamp: Date.now(),
            description: `Safety backup before clearing all data (${studentCount} students)`,
            studentCount: studentCount,
            createdBy: 'System',
            type: 'pre_clear_backup'
        };
        
        // Save backup metadata
        await db.collection('archives').doc(backupId).set(backupData);
        
        // Backup all students
        const backupBatch = db.batch();
        studentsSnapshot.docs.forEach(doc => {
            const backupRef = db.collection('archives')
                .doc(backupId)
                .collection('students')
                .doc(doc.id);
            backupBatch.set(backupRef, {
                ...doc.data(),
                archivedAt: Date.now(),
                originalId: doc.id
            });
        });
        await backupBatch.commit();
        
        showMessage('Backup created successfully. Now clearing data...', 'info');
        
        // Now ask for final confirmation
        const finalConfirm = confirm(
            `✅ Backup has been created successfully!\n\n` +
            `Archive ID: ${backupId}\n` +
            `Students backed up: ${studentCount}\n\n` +
            `Are you ABSOLUTELY SURE you want to clear all student data?\n` +
            `This action cannot be undone (but you can restore from the backup).`
        );
        
        if (!finalConfirm) {
            clearBtn.innerHTML = 'Clear All Data';
            clearBtn.disabled = false;
            showMessage('Clear operation cancelled. Your backup has been saved.', 'info');
            loadArchiveHistory();
            loadArchivesList();
            return;
        }
        
        clearBtn.innerHTML = '<span class="loading"></span>Clearing Data...';
        
        // Clear all student records
        const clearBatch = db.batch();
        studentsSnapshot.docs.forEach(doc => {
            clearBatch.delete(doc.ref);
        });
        await clearBatch.commit();
        
        showMessage(
            `Successfully cleared ${studentCount} student records. ` +
            `A backup has been saved and can be restored from the Archive section.`, 
            'success'
        );
        
        // Update analytics
        await updateAnalytics();
        
        // Reload archive history to show the new backup
        loadArchiveHistory();
        loadArchivesList();
        
        // If on the manage tab, reload the (now empty) student list
        if (document.getElementById('manage-tab').classList.contains('active')) {
            loadStudentData();
        }
        
    } catch (error) {
        console.error('Error clearing student data:', error);
        showMessage('Error clearing data: ' + error.message, 'error');
    } finally {
        const clearBtn = document.getElementById('clear-data-btn');
        if (clearBtn) {
            clearBtn.innerHTML = 'Clear All Data';
            clearBtn.disabled = false;
        }
    }
}

async function deleteEvent(eventId, eventName) {
    // Show confirmation dialog
    const confirmed = confirm(
        `Are you sure you want to delete "${eventName}"?\n\n` +
        'This will permanently delete:\n' +
        '• The event record\n' +
        '• All associated attendance data\n' +
        '• All scan records for this event\n\n' +
        'This action cannot be undone!'
    );
    
    if (!confirmed) {
        return;
    }
    
    try {
        showMessage('Deleting event and notifying mobile apps...', 'info');
        
        // Call the Firebase Function API to delete the event
        // This will also create a deletion notification for mobile apps
        const response = await fetch('https://insession-api-fc.azurewebsites.net/deleteEvent', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                eventId: eventId
            })
        });

        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error || 'Failed to delete event');
        }

        const result = await response.json();
        
        showMessage(
            `Successfully deleted event "${eventName}" and all associated data. ` +
            `${result.deletedScansCount || 0} scans were removed. Mobile apps will be notified.`, 
            'success'
        );
        
        // Reload the events list
        loadEvents();
        
    } catch (error) {
        console.error('Error deleting event:', error);
        showMessage('Error deleting event: ' + error.message, 'error');
    }
}

// New Event Management Functions
async function viewDetailedScans(eventId) {
    try {
        console.log('viewDetailedScans called with eventId:', eventId);
        showMessage('Loading scan details...', 'info');
        
        // Get event details
        const eventDoc = await db.collection('events').doc(eventId).get();
        if (!eventDoc.exists) {
            showMessage('Event not found.', 'error');
            return;
        }
        
        const event = eventDoc.data();
        
        // Get scans from BOTH structures
        const [flatScansSnapshot, nestedScansSnapshot] = await Promise.all([
            // Flat structure - remove orderBy to avoid index requirement, we'll sort in memory
            db.collection('scans')
                .where('listId', '==', eventId)
                .get(),
            // Nested structure (Android app) - also remove orderBy
            db.collection('lists').doc(eventId)
                .collection('scans')
                .get()
        ]);
        
        // Combine all scans
        const allScans = [];
        
        // Add flat structure scans with source indicator
        flatScansSnapshot.docs.forEach(doc => {
            const scanData = doc.data();
            allScans.push({
                ...scanData,
                id: doc.id,
                source: 'Web Portal',
                docPath: `scans/${doc.id}` // Store the document path for deletion
            });
        });
        
        // Add nested structure scans
        nestedScansSnapshot.docs.forEach(doc => {
            const scanData = doc.data();
            allScans.push({
                code: scanData.code,
                timestamp: scanData.timestamp ? new Date(scanData.timestamp).getTime() : Date.now(),
                listId: eventId,
                deviceId: scanData.deviceId || '',
                verified: scanData.processed || false,
                symbology: scanData.symbology || '',
                studentId: scanData.studentId || scanData.code,
                id: doc.id,
                source: 'Android App',
                docPath: `lists/${eventId}/scans/${doc.id}` // Store the nested document path for deletion
            });
        });
        
        // Sort by timestamp (most recent first)
        allScans.sort((a, b) => {
            const timeA = a.timestamp || 0;
            const timeB = b.timestamp || 0;
            return timeB - timeA;
        });
        
        // Look up student details for each scan
        const scansWithDetails = await Promise.all(allScans.map(async (scan) => {
            try {
                const studentDoc = await db.collection('students').doc(scan.code).get();
                if (studentDoc.exists) {
                    const student = studentDoc.data();
                    return {
                        ...scan,
                        firstName: student.firstName || '',
                        lastName: student.lastName || '',
                        email: student.email || '',
                        program: student.program || '',
                        year: student.year || ''
                    };
                }
            } catch (err) {
                // Student not found
            }
            return scan;
        }));
        
        // Store scans globally for bulk delete
        window.currentEventScans = scansWithDetails;
        window.currentEventId = eventId;
        
        // Create detailed view modal
        console.log('Creating modal for event:', event.name, 'with', allScans.length, 'scans');
        
        const modalHTML = `
            <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 1000; display: flex; align-items: center; justify-content: center;">
                <div style="background: white; border-radius: 20px; padding: 30px; width: 90%; max-width: 1200px; max-height: 85vh; display: flex; flex-direction: column; box-shadow: 0 20px 60px rgba(0,0,0,0.3);">
                    <div style="margin-bottom: 20px;">
                        <h2 style="color: #2d3748; margin-bottom: 10px;">Event Scans: ${event.name.replace(/"/g, '&quot;')} (#${event.eventNumber})</h2>
                        <div style="display: flex; gap: 20px; color: #4a5568;">
                            <span><strong>Total Scans:</strong> ${allScans.length}</span>
                            <span><strong>Unique Students:</strong> ${new Set(allScans.map(s => s.code)).size}</span>
                            <span><strong>Web Scans:</strong> ${flatScansSnapshot.size}</span>
                            <span><strong>Android Scans:</strong> ${nestedScansSnapshot.size}</span>
                        </div>
                    </div>
                    
                    <div style="margin-bottom: 15px; display: flex; gap: 10px; align-items: center;">
                        <input type="text" id="scan-search" placeholder="Search by Student ID, Name, or Email..." 
                               onkeyup="filterScans()" 
                               style="flex: 1; padding: 10px; border: 2px solid #e2e8f0; border-radius: 8px;">
                        <button onclick="toggleAllScans()" class="btn btn-secondary" style="padding: 10px 20px;">
                            Select All
                        </button>
                        <button onclick="bulkDeleteScans()" class="btn" style="background: #ef4444; color: white; padding: 10px 20px; display: none;" id="bulk-delete-btn">
                            Delete Selected (<span id="selected-count">0</span>)
                        </button>
                    </div>
                    
                    <div style="flex: 1; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 10px;">
                        <table class="preview-table" style="margin: 0;">
                            <thead style="position: sticky; top: 0; background: white; z-index: 1;">
                                <tr>
                                    <th style="padding: 12px; width: 40px;">
                                        <input type="checkbox" id="select-all-scans" onchange="toggleAllScans()" style="width: 18px; height: 18px; cursor: pointer;">
                                    </th>
                                    <th style="padding: 12px;">#</th>
                                    <th style="padding: 12px;">Student ID</th>
                                    <th style="padding: 12px;">Name</th>
                                    <th style="padding: 12px;">Email</th>
                                    <th style="padding: 12px;">Program</th>
                                    <th style="padding: 12px;">Year</th>
                                    <th style="padding: 12px;">Scan Time</th>
                                    <th style="padding: 12px;">Source</th>
                                    <th style="padding: 12px;">Status</th>
                                </tr>
                            </thead>
                            <tbody id="scans-tbody">
                                ${scansWithDetails.map((scan, index) => `
                                    <tr class="scan-row" data-scan-index="${index}">
                                        <td style="padding: 12px;">
                                            <input type="checkbox" class="scan-checkbox" data-scan-id="${scan.id}" data-scan-path="${scan.docPath}" data-scan-source="${scan.source}" onchange="console.log('Checkbox changed:', this.checked); updateBulkDeleteButton()" style="width: 18px; height: 18px; cursor: pointer;">
                                        </td>
                                        <td style="padding: 12px;">${index + 1}</td>
                                        <td style="padding: 12px;">
                                            <div style="display: flex; align-items: center; gap: 10px;">
                                                <div id="scan-photo-${index}" style="width: 32px; height: 32px; border-radius: 50%; overflow: hidden; background: #f7fafc; display: flex; align-items: center; justify-content: center; border: 1px solid #e2e8f0; font-size: 10px; color: #a0aec0; font-weight: 600;">
                                                    ${scan.code.substring(0, 2).toUpperCase()}
                                                </div>
                                                <span style="font-weight: 600;">${scan.code}</span>
                                            </div>
                                        </td>
                                        <td style="padding: 12px;">${scan.firstName || ''} ${scan.lastName || ''}</td>
                                        <td style="padding: 12px;">${scan.email || '-'}</td>
                                        <td style="padding: 12px;">${scan.program || '-'}</td>
                                        <td style="padding: 12px;">${scan.year || '-'}</td>
                                        <td style="padding: 12px;">${new Date(scan.timestamp).toLocaleString()}</td>
                                        <td style="padding: 12px;">
                                            <span style="background: ${scan.source === 'Web Portal' ? '#bee3f8' : '#c6f6d5'}; 
                                                       color: ${scan.source === 'Web Portal' ? '#2a4365' : '#22543d'}; 
                                                       padding: 2px 8px; border-radius: 12px; font-size: 0.85rem;">
                                                ${scan.source}
                                            </span>
                                        </td>
                                        <td style="padding: 12px;">
                                            ${scan.verified || (scan.firstName && scan.lastName) ? 
                                              '<span style="color: #22543d;">✅ Verified</span>' : 
                                              '<span style="color: #e53e3e;">❌ Not Found</span>'}
                                        </td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                    
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 20px;">
                        <div>
                            <button class="btn btn-secondary" onclick="exportDetailedReport('${eventId}')">Export Detailed Report</button>
                        </div>
                        <button class="btn btn-primary" onclick="closeScanDetails()">Close</button>
                    </div>
                </div>
            </div>
        `;
        
        // Create and append modal
        console.log('Creating modal div and appending to body');
        const modalDiv = document.createElement('div');
        modalDiv.id = 'scan-details-modal';
        modalDiv.innerHTML = modalHTML;
        document.body.appendChild(modalDiv);
        
        // Store scans data for filtering
        window.currentScansData = scansWithDetails;
        
        // Load student photos for the scan modal
        scansWithDetails.forEach((scan, index) => {
            getStudentImageUrl(scan.code).then(imageUrl => {
                const photoElement = document.getElementById(`scan-photo-${index}`);
                if (photoElement && imageUrl) {
                    photoElement.innerHTML = `
                        <img src="${imageUrl}" 
                             alt="Student ${scan.code}" 
                             style="width: 100%; height: 100%; object-fit: cover;"
                             onerror="this.style.display='none'">
                    `;
                }
            });
        });
        
        console.log('Modal created and added to DOM');
        clearMessage();
        
    } catch (error) {
        console.error('Error loading scan details:', error);
        showMessage('Error loading scan details: ' + error.message, 'error');
    }
}

function filterScans() {
    const searchTerm = document.getElementById('scan-search').value.toLowerCase();
    const rows = document.querySelectorAll('#scans-tbody .scan-row');
    
    rows.forEach(row => {
        const text = row.textContent.toLowerCase();
        row.style.display = text.includes(searchTerm) ? '' : 'none';
    });
}

function closeScanDetails() {
    const modal = document.getElementById('scan-details-modal');
    if (modal) {
        modal.remove();
    }
    window.currentScansData = null;
    window.currentEventScans = null;
    window.currentEventId = null;
}

// Bulk delete functions
function toggleAllScans() {
    const selectAllCheckbox = document.getElementById('select-all-scans');
    const checkboxes = document.querySelectorAll('.scan-checkbox');
    const isChecked = selectAllCheckbox.checked;
    
    console.log('toggleAllScans: Setting', checkboxes.length, 'checkboxes to', isChecked);
    
    checkboxes.forEach(checkbox => {
        checkbox.checked = isChecked;
    });
    
    updateBulkDeleteButton();
}

function updateBulkDeleteButton() {
    const checkboxes = document.querySelectorAll('.scan-checkbox:checked');
    const bulkDeleteBtn = document.getElementById('bulk-delete-btn');
    const selectedCount = document.getElementById('selected-count');
    
    console.log('updateBulkDeleteButton: Found', checkboxes.length, 'selected checkboxes');
    
    if (checkboxes.length > 0) {
        bulkDeleteBtn.style.display = 'inline-block';
        selectedCount.textContent = checkboxes.length;
        console.log('Bulk delete button should now be visible');
    } else {
        bulkDeleteBtn.style.display = 'none';
        console.log('Bulk delete button hidden');
    }
    
    // Update select all checkbox state
    const allCheckboxes = document.querySelectorAll('.scan-checkbox');
    const selectAllCheckbox = document.getElementById('select-all-scans');
    console.log('Found', allCheckboxes.length, 'total checkboxes');
    if (allCheckboxes.length > 0) {
        selectAllCheckbox.checked = checkboxes.length === allCheckboxes.length;
    }
}

async function bulkDeleteScans() {
    const checkboxes = document.querySelectorAll('.scan-checkbox:checked');
    
    if (checkboxes.length === 0) {
        showMessage('No scans selected for deletion.', 'error');
        return;
    }
    
    const confirmMessage = `Are you sure you want to delete ${checkboxes.length} selected scan(s)? This action cannot be undone.`;
    
    if (!confirm(confirmMessage)) {
        return;
    }
    
    showMessage(`Deleting ${checkboxes.length} scans...`, 'info');
    
    const deletePromises = [];
    const batch = db.batch();
    let batchCount = 0;
    const maxBatchSize = 500; // Firestore batch limit
    
    for (const checkbox of checkboxes) {
        const scanPath = checkbox.dataset.scanPath;
        const scanSource = checkbox.dataset.scanSource;
        
        if (scanSource === 'Web Portal') {
            // Delete from flat structure
            const docRef = db.doc(scanPath);
            batch.delete(docRef);
            batchCount++;
        } else if (scanSource === 'Android App') {
            // Delete from nested structure
            const pathParts = scanPath.split('/');
            const docRef = db.collection('lists').doc(pathParts[1]).collection('scans').doc(pathParts[3]);
            batch.delete(docRef);
            batchCount++;
        }
        
        // If we reach the batch limit, commit and start a new batch
        if (batchCount >= maxBatchSize) {
            deletePromises.push(batch.commit());
            batchCount = 0;
        }
    }
    
    // Commit any remaining deletes
    if (batchCount > 0) {
        deletePromises.push(batch.commit());
    }
    
    try {
        await Promise.all(deletePromises);
        showMessage(`Successfully deleted ${checkboxes.length} scan(s).`, 'success');
        
        // Refresh the scan view
        setTimeout(() => {
            closeScanDetails();
            if (window.currentEventId) {
                viewDetailedScans(window.currentEventId);
            }
        }, 1500);
        
    } catch (error) {
        console.error('Error deleting scans:', error);
        showMessage(`Error deleting scans: ${error.message}`, 'error');
    }
}

async function exportDetailedReport(eventId) {
    if (!window.currentScansData) {
        showMessage('No scan data available to export.', 'error');
        return;
    }
    
    try {
        // Create worksheet data
        const worksheetData = [
            ['#', 'Student ID', 'First Name', 'Last Name', 'Email', 'Program', 'Year', 'Scan Time', 'Source', 'Status']
        ];
        
        window.currentScansData.forEach((scan, index) => {
            worksheetData.push([
                index + 1,
                scan.code,
                scan.firstName || '',
                scan.lastName || '',
                scan.email || '',
                scan.program || '',
                scan.year || '',
                new Date(scan.timestamp).toLocaleString(),
                scan.source,
                (scan.verified || (scan.firstName && scan.lastName)) ? 'Verified' : 'Not Found'
            ]);
        });
        
        // Create workbook and worksheet
        const wb = XLSX.utils.book_new();
        const ws = XLSX.utils.aoa_to_sheet(worksheetData);
        XLSX.utils.book_append_sheet(wb, ws, 'Detailed Scans');
        
        // Download the file
        const today = new Date();
        const dateString = `${today.getFullYear()}${(today.getMonth() + 1).toString().padStart(2, '0')}${today.getDate().toString().padStart(2, '0')}`;
        const filename = `Event_Detailed_Report_${dateString}.xlsx`;
        
        XLSX.writeFile(wb, filename);
        showMessage(`Exported detailed report with ${window.currentScansData.length} scans.`, 'success');
        
    } catch (error) {
        console.error('Error exporting detailed report:', error);
        showMessage('Error exporting report: ' + error.message, 'error');
    }
}

async function editEventNumber(eventId, currentNumber) {
    const newNumber = prompt(`Enter new event ID number (current: ${currentNumber}):`, currentNumber);
    
    if (newNumber === null || newNumber === '') {
        return;
    }
    
    const newNumberInt = parseInt(newNumber);
    if (isNaN(newNumberInt)) {
        showMessage('Please enter a valid number.', 'error');
        return;
    }
    
    if (newNumberInt === currentNumber) {
        return;
    }
    
    try {
        // Check if new number already exists
        const existingEvent = await db.collection('events')
            .where('eventNumber', '==', newNumberInt)
            .get();
        
        if (!existingEvent.empty) {
            showMessage(`Event number ${newNumberInt} is already in use. Please choose a different number.`, 'error');
            return;
        }
        
        // Update the event number
        await db.collection('events').doc(eventId).update({
            eventNumber: newNumberInt
        });
        
        showMessage(`Event ID updated from ${currentNumber} to ${newNumberInt}.`, 'success');
        loadEvents();
        
    } catch (error) {
        console.error('Error updating event number:', error);
        showMessage('Error updating event ID: ' + error.message, 'error');
    }
}

// Manual Student Entry Functions
function showAddStudentForm() {
    document.getElementById('add-student-form').classList.remove('hidden');
    document.getElementById('new-student-id').focus();
}

function hideAddStudentForm() {
    document.getElementById('add-student-form').classList.add('hidden');
    clearAddStudentForm();
}

function clearAddStudentForm() {
    document.getElementById('new-student-id').value = '';
    document.getElementById('new-student-firstname').value = '';
    document.getElementById('new-student-lastname').value = '';
    document.getElementById('new-student-email').value = '';
}

async function addNewStudent() {
    const studentId = document.getElementById('new-student-id').value.trim();
    const firstName = document.getElementById('new-student-firstname').value.trim();
    const lastName = document.getElementById('new-student-lastname').value.trim();
    const email = document.getElementById('new-student-email').value.trim();
    
    // Validate required fields
    if (!studentId || !firstName || !lastName) {
        showMessage('Please fill in all required fields (Student ID, First Name, Last Name).', 'error');
        return;
    }
    
    // Validate student ID format (should be 9 digits)
    if (!/^\d{9}$/.test(studentId)) {
        showMessage('Student ID must be exactly 9 digits.', 'error');
        return;
    }
    
    const addBtn = document.getElementById('add-student-btn');
    addBtn.innerHTML = '<span class="loading"></span>Adding...';
    addBtn.disabled = true;
    
    try {
        // Check if student ID already exists
        const existingStudent = await db.collection('students').doc(studentId).get();
        
        if (existingStudent.exists) {
            showMessage(`Student ID ${studentId} already exists in the database.`, 'error');
            addBtn.innerHTML = 'Add Student';
            addBtn.disabled = false;
            return;
        }
        
        // Create new student document
        const studentDoc = {
            studentId: studentId,
            firstName: firstName,
            lastName: lastName,
            email: email || '',
            program: '',
            year: '',
            uploadedAt: firebase.firestore.FieldValue.serverTimestamp(),
            addedManually: true,
            active: true
        };
        
        await db.collection('students').doc(studentId).set(studentDoc);
        
        showMessage(`Successfully added ${firstName} ${lastName} (ID: ${studentId}) to the database.`, 'success');
        
        // Clear form and hide it
        hideAddStudentForm();
        
        // Update analytics
        await updateAnalytics();
        
        // Reload student data if we're on the manage tab
        if (document.getElementById('manage-tab').classList.contains('active')) {
            loadStudentData();
        }
        
    } catch (error) {
        console.error('Error adding student:', error);
        showMessage('Error adding student: ' + error.message, 'error');
    } finally {
        addBtn.innerHTML = 'Add Student';
        addBtn.disabled = false;
    }
}

// Student Action Functions
function executeStudentAction(studentId, studentNumber, firstName, lastName) {
    const selectElement = document.getElementById(`student-action-${studentId}`);
    const action = selectElement.value;
    
    if (!action) {
        showMessage('Please select an action first.', 'error');
        return;
    }
    
    switch(action) {
        case 'view':
            viewStudentDetails(studentId);
            break;
        case 'edit':
            editStudent(studentId);
            break;
        case 'export':
            exportStudentData(studentId, studentNumber, firstName, lastName);
            break;
        case 'delete':
            deleteStudent(studentId, studentNumber, firstName, lastName);
            break;
        default:
            showMessage('Invalid action selected.', 'error');
    }
    
    // Reset the dropdown
    selectElement.value = '';
}

async function viewStudentDetails(studentId) {
    try {
        const studentDoc = await db.collection('students').doc(studentId).get();
        
        if (!studentDoc.exists) {
            showMessage('Student not found.', 'error');
            return;
        }
        
        const student = studentDoc.data();
        
        const content = `
            <div class="info-section" style="display: flex; gap: 20px; align-items: flex-start;">
                <div id="student-detail-photo" style="width: 80px; height: 80px; border-radius: 50%; overflow: hidden; background: #f7fafc; display: flex; align-items: center; justify-content: center; border: 2px solid #e2e8f0; flex-shrink: 0;">
                    <div style="color: #a0aec0; font-size: 16px; font-weight: 600;">
                        ${student.studentId ? student.studentId.substring(0, 2).toUpperCase() : '??'}
                    </div>
                </div>
                <div style="flex: 1;">
                    <h3>Student Information</h3>
                    <p><strong>Student ID:</strong> ${student.studentId || 'N/A'}</p>
                    <p><strong>Name:</strong> ${student.firstName || ''} ${student.lastName || ''}</p>
                    <p><strong>Email:</strong> ${student.email || 'N/A'}</p>
                    <p><strong>Program:</strong> ${student.program || 'Not specified'}</p>
                    <p><strong>Year:</strong> ${student.year || 'Not specified'}</p>
                    <p><strong>Status:</strong> ${student.active ? 'Active' : 'Inactive'}</p>
                    <p><strong>Added:</strong> ${tsToMillis(student.uploadedAt) ? new Date(tsToMillis(student.uploadedAt)).toLocaleString() : 'Unknown'}</p>
                    <p><strong>Added Method:</strong> ${student.addedManually ? 'Manual Entry' : 'CSV Upload'}</p>
                </div>
            </div>
            
            <div class="info-section">
                <h3>Scan History</h3>
                <p style="color: #6b7280;">Loading scan history...</p>
            </div>
        `;
        
        showModal(`Student Details: ${student.firstName} ${student.lastName}`, content);
        
        // Load student photo
        getStudentImageUrl(student.studentId).then(imageUrl => {
            const photoElement = document.getElementById('student-detail-photo');
            if (photoElement && imageUrl) {
                photoElement.innerHTML = `
                    <img src="${imageUrl}" 
                         alt="Student ${student.studentId}" 
                         style="width: 100%; height: 100%; object-fit: cover;"
                         onerror="this.style.display='none'">
                `;
            }
        });
        
        // Load scan history
        loadStudentScanHistory(studentId);
        
    } catch (error) {
        console.error('Error viewing student details:', error);
        showMessage('Error loading student details: ' + error.message, 'error');
    }
}

async function loadStudentScanHistory(studentId) {
    try {
        const scansSnapshot = await db.collection('scans')
            .where('code', '==', studentId)
            .limit(20)
            .get();
        
        const modalBody = document.getElementById('modal-body');
        const scanSection = modalBody.querySelector('.info-section:last-child');
        
        if (scansSnapshot.empty) {
            scanSection.innerHTML = '<h3>Scan History</h3><p style="color: #6b7280;">No scan history found for this student.</p>';
        } else {
            let scanHTML = '<h3>Scan History</h3><div style="max-height: 200px; overflow-y: auto;">';
            
            scansSnapshot.docs.forEach(doc => {
                const scan = doc.data();
                const timestamp = new Date(scan.timestamp);
                scanHTML += `
                    <div style="padding: 8px; border-bottom: 1px solid #e5e7eb;">
                        <strong>Event:</strong> ${scan.listId || 'Unknown'}<br>
                        <strong>Time:</strong> ${timestamp.toLocaleString()}<br>
                        <strong>Status:</strong> ${scan.verified ? '✅ Verified' : '❌ Not Verified'}
                    </div>
                `;
            });
            
            scanHTML += '</div>';
            scanSection.innerHTML = scanHTML;
        }
        
    } catch (error) {
        console.error('Error loading scan history:', error);
    }
}

function editStudent(studentId) {
    showMessage('Edit functionality coming soon!', 'info');
}

function exportStudentData(studentId, studentNumber, firstName, lastName) {
    const csvContent = `StudentID,FirstName,LastName,Email\n${studentNumber},${firstName},${lastName},`;
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    
    if (link.download !== undefined) {
        const url = URL.createObjectURL(blob);
        link.setAttribute('href', url);
        link.setAttribute('download', `student_${studentNumber}.csv`);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
    
    showMessage(`Exported data for ${firstName} ${lastName}`, 'success');
}

async function deleteStudent(studentId, studentNumber, firstName, lastName) {
    const confirmed = confirm(
        `Are you sure you want to delete this student?\n\n` +
        `Student ID: ${studentNumber}\n` +
        `Name: ${firstName} ${lastName}\n\n` +
        `This action cannot be undone!`
    );
    
    if (!confirmed) {
        return;
    }
    
    try {
        await db.collection('students').doc(studentId).delete();
        
        showMessage(`Successfully deleted student ${firstName} ${lastName} (ID: ${studentNumber})`, 'success');
        
        // Reload student data
        loadStudentData();
        
    } catch (error) {
        console.error('Error deleting student:', error);
        showMessage('Error deleting student: ' + error.message, 'error');
    }
}

// Archive Management Functions
async function createArchive() {
    const description = document.getElementById('archive-description').value.trim();
    const createBtn = document.getElementById('create-archive-btn');
    
    createBtn.innerHTML = '<span class="loading"></span>Creating Archive...';
    createBtn.disabled = true;
    
    try {
        // Get all current students
        const studentsSnapshot = await db.collection('students').get();
        
        if (studentsSnapshot.empty) {
            showMessage('No student data to archive.', 'error');
            createBtn.innerHTML = 'Create Archive Backup';
            createBtn.disabled = false;
            return;
        }
        
        // Create archive metadata
        const archiveId = `archive_${Date.now()}`;
        const archiveData = {
            id: archiveId,
            createdAt: firebase.firestore.FieldValue.serverTimestamp(),
            timestamp: Date.now(),
            description: description || 'Manual backup',
            studentCount: studentsSnapshot.size,
            createdBy: 'Admin Portal',
            type: 'full_backup'
        };
        
        // Save archive metadata
        await db.collection('archives').doc(archiveId).set(archiveData);
        
        // Create batch for archiving students
        const batch = db.batch();
        let archivedCount = 0;
        
        studentsSnapshot.docs.forEach(doc => {
            const studentData = doc.data();
            const archiveStudentRef = db.collection('archives')
                .doc(archiveId)
                .collection('students')
                .doc(doc.id);
            
            batch.set(archiveStudentRef, {
                ...studentData,
                archivedAt: Date.now(),
                originalId: doc.id
            });
            archivedCount++;
        });
        
        await batch.commit();
        
        showMessage(`Successfully archived ${archivedCount} student records.`, 'success');
        
        // Clear the description field
        document.getElementById('archive-description').value = '';
        
        // Reload archive history
        loadArchiveHistory();
        loadArchivesList();
        
    } catch (error) {
        console.error('Error creating archive:', error);
        showMessage('Error creating archive: ' + error.message, 'error');
    } finally {
        createBtn.innerHTML = 'Create Archive Backup';
        createBtn.disabled = false;
    }
}

async function loadArchivesList() {
    try {
        const archivesSnapshot = await db.collection('archives')
            .orderBy('timestamp', 'desc')
            .get();
        
        const selectElement = document.getElementById('archive-select');
        
        if (archivesSnapshot.empty) {
            selectElement.innerHTML = '<option value="">No archives available</option>';
            return;
        }
        
        selectElement.innerHTML = '<option value="">Select an archive...</option>';
        
        archivesSnapshot.docs.forEach(doc => {
            const archive = doc.data();
            const date = new Date(archive.timestamp);
            const dateString = date.toLocaleString();
            const option = document.createElement('option');
            option.value = doc.id;
            option.textContent = `${dateString} - ${archive.description} (${archive.studentCount} students)`;
            selectElement.appendChild(option);
        });
        
    } catch (error) {
        console.error('Error loading archives:', error);
    }
}

async function loadArchiveHistory() {
    try {
        const archivesSnapshot = await db.collection('archives')
            .orderBy('timestamp', 'desc')
            .limit(10)
            .get();
        
        const historyDiv = document.getElementById('archive-history');
        
        if (archivesSnapshot.empty) {
            historyDiv.innerHTML = '<p style="color: #718096; text-align: center;">No archives created yet.</p>';
            return;
        }
        
        let historyHTML = '<div style="overflow-x: auto;"><table class="preview-table">';
        historyHTML += `
            <thead>
                <tr>
                    <th>Date & Time</th>
                    <th>Description</th>
                    <th>Students</th>
                    <th>Created By</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
        `;
        
        archivesSnapshot.docs.forEach(doc => {
            const archive = doc.data();
            const date = new Date(archive.timestamp);
            const dateString = date.toLocaleString();
            
            historyHTML += `
                <tr>
                    <td>${dateString}</td>
                    <td>${archive.description}</td>
                    <td>${archive.studentCount}</td>
                    <td>${archive.createdBy}</td>
                    <td>
                        <button class="btn btn-secondary" style="padding: 5px 10px; font-size: 0.9rem; margin-right: 5px;" 
                                onclick="viewArchiveById('${doc.id}')">View</button>
                        <button class="btn btn-primary" style="padding: 5px 10px; font-size: 0.9rem; margin-right: 5px; background: #f6ad55;" 
                                onclick="restoreArchiveById('${doc.id}')">Restore</button>
                        <button class="btn" style="padding: 5px 10px; font-size: 0.9rem; background: #fed7d7; color: #742a2a;" 
                                onclick="deleteArchive('${doc.id}')">Delete</button>
                    </td>
                </tr>
            `;
        });
        
        historyHTML += '</tbody></table></div>';
        historyDiv.innerHTML = historyHTML;
        
    } catch (error) {
        console.error('Error loading archive history:', error);
        document.getElementById('archive-history').innerHTML = 
            '<p style="color: #e53e3e; text-align: center;">Error loading archive history.</p>';
    }
}

async function viewArchive() {
    const archiveId = document.getElementById('archive-select').value;
    if (!archiveId) {
        showMessage('Please select an archive to view.', 'error');
        return;
    }
    
    await viewArchiveById(archiveId);
}

async function viewArchiveById(archiveId) {
    const viewBtn = document.getElementById('view-archive-btn');
    if (viewBtn) {
        viewBtn.innerHTML = '<span class="loading"></span>Loading...';
        viewBtn.disabled = true;
    }
    
    try {
        // Get archive metadata
        const archiveDoc = await db.collection('archives').doc(archiveId).get();
        if (!archiveDoc.exists) {
            showMessage('Archive not found.', 'error');
            return;
        }
        
        const archive = archiveDoc.data();
        
        // Get archived students
        const studentsSnapshot = await db.collection('archives')
            .doc(archiveId)
            .collection('students')
            .limit(100)
            .get();
        
        // Create preview modal content
        const date = new Date(archive.timestamp);
        let previewHTML = `
            <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 1000; display: flex; align-items: center; justify-content: center;">
                <div style="background: white; border-radius: 20px; padding: 30px; max-width: 90%; max-height: 80%; overflow: auto; box-shadow: 0 20px 60px rgba(0,0,0,0.3);">
                    <h2 style="color: #2d3748; margin-bottom: 20px;">Archive Preview</h2>
                    <div style="margin-bottom: 20px;">
                        <strong>Created:</strong> ${date.toLocaleString()}<br>
                        <strong>Description:</strong> ${archive.description}<br>
                        <strong>Total Students:</strong> ${archive.studentCount}
                    </div>
                    <div style="max-height: 400px; overflow-y: auto;">
                        <table class="preview-table">
                            <thead>
                                <tr>
                                    <th>Student ID</th>
                                    <th>First Name</th>
                                    <th>Last Name</th>
                                    <th>Email</th>
                                    <th>Program</th>
                                    <th>Year</th>
                                </tr>
                            </thead>
                            <tbody>
        `;
        
        studentsSnapshot.docs.forEach(doc => {
            const student = doc.data();
            previewHTML += `
                <tr>
                    <td>${student.studentId || ''}</td>
                    <td>${student.firstName || ''}</td>
                    <td>${student.lastName || ''}</td>
                    <td>${student.email || ''}</td>
                    <td>${student.program || ''}</td>
                    <td>${student.year || ''}</td>
                </tr>
            `;
        });
        
        if (archive.studentCount > 100) {
            previewHTML += `
                <tr>
                    <td colspan="6" style="text-align: center; font-style: italic; color: #718096;">
                        ... and ${archive.studentCount - 100} more students
                    </td>
                </tr>
            `;
        }
        
        previewHTML += `
                            </tbody>
                        </table>
                    </div>
                    <div style="text-align: right; margin-top: 20px;">
                        <button class="btn btn-secondary" onclick="closeArchivePreview()">Close</button>
                        <button class="btn btn-primary" style="background: #28a745;" onclick="exportArchive('${archiveId}')">Export as CSV</button>
                    </div>
                </div>
            </div>
        `;
        
        // Create and append preview div
        const previewDiv = document.createElement('div');
        previewDiv.id = 'archive-preview-modal';
        previewDiv.innerHTML = previewHTML;
        document.body.appendChild(previewDiv);
        
    } catch (error) {
        console.error('Error viewing archive:', error);
        showMessage('Error viewing archive: ' + error.message, 'error');
    } finally {
        if (viewBtn) {
            viewBtn.innerHTML = 'View Archive';
            viewBtn.disabled = false;
        }
    }
}

function closeArchivePreview() {
    const modal = document.getElementById('archive-preview-modal');
    if (modal) {
        modal.remove();
    }
}

async function restoreArchive() {
    const archiveId = document.getElementById('archive-select').value;
    if (!archiveId) {
        showMessage('Please select an archive to restore.', 'error');
        return;
    }
    
    await restoreArchiveById(archiveId);
}

async function restoreArchiveById(archiveId) {
    const confirmed = confirm(
        'Are you sure you want to restore this archive?\n\n' +
        'This will:\n' +
        '• Replace ALL current student data\n' +
        '• The current data will be automatically backed up first\n\n' +
        'Continue?'
    );
    
    if (!confirmed) {
        return;
    }
    
    const restoreBtn = document.getElementById('restore-archive-btn');
    if (restoreBtn) {
        restoreBtn.innerHTML = '<span class="loading"></span>Restoring...';
        restoreBtn.disabled = true;
    }
    
    try {
        // First, create a backup of current data
        showMessage('Creating backup of current data...', 'info');
        
        const currentSnapshot = await db.collection('students').get();
        if (!currentSnapshot.empty) {
            // Create automatic backup
            const backupId = `auto_backup_${Date.now()}`;
            const backupData = {
                id: backupId,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                timestamp: Date.now(),
                description: `Automatic backup before restore from ${new Date().toLocaleString()}`,
                studentCount: currentSnapshot.size,
                createdBy: 'System',
                type: 'auto_backup_before_restore'
            };
            
            await db.collection('archives').doc(backupId).set(backupData);
            
            // Backup current students
            const backupBatch = db.batch();
            currentSnapshot.docs.forEach(doc => {
                const backupRef = db.collection('archives')
                    .doc(backupId)
                    .collection('students')
                    .doc(doc.id);
                backupBatch.set(backupRef, {
                    ...doc.data(),
                    archivedAt: Date.now(),
                    originalId: doc.id
                });
            });
            await backupBatch.commit();
        }
        
        showMessage('Restoring archive data...', 'info');
        
        // Get archive metadata
        const archiveDoc = await db.collection('archives').doc(archiveId).get();
        if (!archiveDoc.exists) {
            showMessage('Archive not found.', 'error');
            return;
        }
        
        // Get all archived students
        const archivedStudentsSnapshot = await db.collection('archives')
            .doc(archiveId)
            .collection('students')
            .get();
        
        // Clear current students collection
        const clearBatch = db.batch();
        currentSnapshot.docs.forEach(doc => {
            clearBatch.delete(doc.ref);
        });
        await clearBatch.commit();
        
        // Restore archived students
        const restoreBatch = db.batch();
        let restoredCount = 0;
        
        archivedStudentsSnapshot.docs.forEach(doc => {
            const studentData = doc.data();
            const originalId = studentData.originalId || doc.id;
            
            // Remove archive-specific fields
            delete studentData.archivedAt;
            delete studentData.originalId;
            
            const studentRef = db.collection('students').doc(originalId);
            restoreBatch.set(studentRef, {
                ...studentData,
                restoredAt: firebase.firestore.FieldValue.serverTimestamp(),
                restoredFrom: archiveId
            });
            restoredCount++;
        });
        
        await restoreBatch.commit();
        
        showMessage(`Successfully restored ${restoredCount} student records from archive.`, 'success');
        
        // Update analytics
        await updateAnalytics();
        
        // Reload archive history
        loadArchiveHistory();
        
        // If on the manage tab, reload the student data
        if (document.getElementById('manage-tab').classList.contains('active')) {
            loadStudentData();
        }
        
    } catch (error) {
        console.error('Error restoring archive:', error);
        showMessage('Error restoring archive: ' + error.message, 'error');
    } finally {
        if (restoreBtn) {
            restoreBtn.innerHTML = 'Restore Data';
            restoreBtn.disabled = false;
        }
    }
}

async function deleteArchive(archiveId) {
    const confirmed = confirm(
        'Are you sure you want to delete this archive?\n\n' +
        'This will permanently delete the archive and all its data.\n' +
        'This action cannot be undone!'
    );
    
    if (!confirmed) {
        return;
    }
    
    try {
        showMessage('Deleting archive...', 'info');
        
        // Delete all students in the archive
        const studentsSnapshot = await db.collection('archives')
            .doc(archiveId)
            .collection('students')
            .get();
        
        const batch = db.batch();
        
        studentsSnapshot.docs.forEach(doc => {
            batch.delete(doc.ref);
        });
        
        // Delete the archive metadata
        batch.delete(db.collection('archives').doc(archiveId));
        
        await batch.commit();
        
        showMessage('Archive deleted successfully.', 'success');
        
        // Reload archive history and list
        loadArchiveHistory();
        loadArchivesList();
        
    } catch (error) {
        console.error('Error deleting archive:', error);
        showMessage('Error deleting archive: ' + error.message, 'error');
    }
}

async function exportArchive(archiveId) {
    try {
        // Get archived students
        const studentsSnapshot = await db.collection('archives')
            .doc(archiveId)
            .collection('students')
            .get();
        
        const students = studentsSnapshot.docs.map(doc => doc.data());
        const csvContent = generateCSVFromStudents(students);
        
        const archiveDoc = await db.collection('archives').doc(archiveId).get();
        const archive = archiveDoc.data();
        const date = new Date(archive.timestamp);
        const dateString = `${date.getFullYear()}${(date.getMonth() + 1).toString().padStart(2, '0')}${date.getDate().toString().padStart(2, '0')}`;
        
        downloadCSV(csvContent, `archive_${dateString}_${archive.studentCount}_students.csv`);
        showMessage('Archive exported successfully.', 'success');
        
    } catch (error) {
        console.error('Error exporting archive:', error);
        showMessage('Error exporting archive: ' + error.message, 'error');
    }
}

// Notification System
let notifications = [];
let completedEvents = [];

function checkForCompletedEvents() {
    // Check localStorage for completed events
    const storedEvents = localStorage.getItem('completedEvents');
    if (storedEvents) {
        completedEvents = JSON.parse(storedEvents);
        updateNotificationBadge();
    }
}

function addEventCompletionNotification(eventName, eventNumber) {
    const notification = {
        id: Date.now(),
        type: 'event_complete',
        title: 'Event Completed',
        message: `Event #${eventNumber}: ${eventName} has been marked as complete.`,
        timestamp: new Date().toISOString(),
        read: false
    };
    
    notifications.unshift(notification);
    completedEvents.push(notification);
    localStorage.setItem('completedEvents', JSON.stringify(completedEvents));
    updateNotificationBadge();
    
    // Show toast notification
    showToastNotification(`✅ Event "${eventName}" completed!`);
}

function updateNotificationBadge() {
    const unreadCount = notifications.filter(n => !n.read).length;
    const badge = document.getElementById('notification-count');
    
    if (unreadCount > 0) {
        badge.textContent = unreadCount;
        badge.style.display = 'inline-block';
    } else {
        badge.style.display = 'none';
    }
}

function showToastNotification(message) {
    const toast = document.createElement('div');
    toast.className = 'toast-notification';
    toast.innerHTML = `
        <div style="position: fixed; bottom: 20px; right: 20px; background: #10b981; color: white; padding: 16px 24px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); z-index: 3000; animation: slideInUp 0.3s ease;">
            ${message}
        </div>
    `;
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.remove();
    }, 3000);
}

// Modal Functions
function showModal(title, content) {
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-body').innerHTML = content;
    document.getElementById('modal-overlay').style.display = 'flex';
}

function closeModal() {
    document.getElementById('modal-overlay').style.display = 'none';
}

function showNotifications() {
    let content = '<div>';
    
    if (notifications.length === 0) {
        content += '<p style="text-align: center; color: #6b7280; padding: 32px;">No notifications yet</p>';
    } else {
        notifications.forEach(notif => {
            const date = new Date(notif.timestamp);
            content += `
                <div class="help-item" style="${!notif.read ? 'background: #eff6ff; border-color: #3b82f6;' : ''}">
                    <div style="display: flex; justify-content: space-between; align-items: start;">
                        <div>
                            <h4>${notif.title}</h4>
                            <p>${notif.message}</p>
                            <small style="color: #9ca3af;">${date.toLocaleString()}</small>
                        </div>
                        ${!notif.read ? '<span style="color: #3b82f6; font-size: 0.75rem; font-weight: 600;">NEW</span>' : ''}
                    </div>
                </div>
            `;
            notif.read = true;
        });
    }
    
    content += '</div>';
    
    showModal('Notifications', content);
    updateNotificationBadge();
}

function showInfo() {
    const content = `
        <div class="info-section">
            <h3>System Information</h3>
            <p><strong>Created By:</strong> Andrew Gregware</p>
            <p><strong>Creation Date:</strong> August 29, 2025</p>
            <p><strong>Last Updated:</strong> ${new Date().toLocaleDateString()}</p>
            <p><strong>Version:</strong> 2.0.0</p>
            <p><strong>Database:</strong> Firebase Firestore</p>
        </div>
        
        <div class="info-section">
            <h3>Features</h3>
            <p>• Student data management with CSV upload</p>
            <p>• Event creation and attendance tracking</p>
            <p>• Archive system for data backup/restore</p>
            <p>• Real-time analytics and reporting</p>
            <p>• QR code scanning integration</p>
        </div>
        
        <div class="info-section">
            <h3>Data Limits</h3>
            <p>• Maximum CSV size: 10MB</p>
            <p>• Student ID format: 9 digits</p>
            <p>• Archive retention: Unlimited</p>
        </div>
    `;
    
    showModal('System Information', content);
}

function showHelp() {
    const content = `
        <div class="help-item">
            <h4>How to Upload Students</h4>
            <p>1. Click "Download CSV Template" to get the correct format</p>
            <p>2. Fill in StudentID, FirstName, LastName, and Email</p>
            <p>3. Drag and drop or click to upload the CSV file</p>
            <p>4. Click "Upload to Database" to import students</p>
        </div>
        
        <div class="help-item">
            <h4>Creating Events</h4>
            <p>1. Go to the Events tab</p>
            <p>2. Click "Create New Event"</p>
            <p>3. Enter a unique event number and name</p>
            <p>4. Events are automatically set to active status</p>
        </div>
        
        <div class="help-item">
            <h4>Managing Archives</h4>
            <p>• Create Archive: Backs up all current student data</p>
            <p>• Restore Archive: Replaces current data with archived version</p>
            <p>• Archives are timestamped and can be exported as CSV</p>
        </div>
        
        <div class="help-item">
            <h4>Keyboard Shortcuts</h4>
            <p><strong>Ctrl + S:</strong> Save current form</p>
            <p><strong>Ctrl + F:</strong> Focus search box</p>
            <p><strong>Esc:</strong> Close modal windows</p>
        </div>
        
        <div class="help-item">
            <h4>Need More Help?</h4>
            <p>Contact support at: agregware@charlestonlaw.edu</p>
            <p>Documentation: docs.insession.com</p>
        </div>
    `;
    
    showModal('Help & Documentation', content);
}

// Add keyboard shortcuts
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeModal();
        closeScanDetails();
        closeArchivePreview();
    }
});

// Student photo management functions
async function checkStudentPhotos() {
    try {
        showMessage('Checking student photos in Firebase Storage...', 'info');
        
        const checkBtn = document.querySelector('[onclick="checkStudentPhotos()"]');
        const originalText = checkBtn.textContent;
        checkBtn.textContent = 'Checking...';
        checkBtn.disabled = true;
        
        const response = await fetch('https://insession-api-fc.azurewebsites.net/checkStudentPhotos', {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
            }
        });

        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error || 'Failed to check student photos');
        }

        const result = await response.json();
        const summary = result.summary;
        
        showMessage(
            `Photo check complete! Found ${summary.photosFound} students with photos, ` +
            `${summary.photosNotFound} without photos. Updated ${summary.recordsUpdated} records.`,
            'success'
        );
        
        // Refresh the student data to show updated photo status
        await loadStudentData();
        updatePhotoFilterCount();
        
        checkBtn.textContent = originalText;
        checkBtn.disabled = false;
        
    } catch (error) {
        console.error('Error checking student photos:', error);
        showMessage('Error checking photos: ' + error.message, 'error');
        
        const checkBtn = document.querySelector('[onclick="checkStudentPhotos()"]');
        checkBtn.textContent = 'Check Photos';
        checkBtn.disabled = false;
    }
}

async function filterStudentsByPhoto() {
    const filter = document.getElementById('photo-filter').value;
    console.log('Filtering students by photo:', filter);
    
    try {
        let hasPhotoParam = null;
        if (filter === 'with-photos') {
            hasPhotoParam = 'true';
        } else if (filter === 'without-photos') {
            hasPhotoParam = 'false';
        }
        
        // Build URL with photo filter
        let url = 'https://insession-api-fc.azurewebsites.net/getStudentsWithPhotos?includePhotos=true';
        if (hasPhotoParam) {
            url += `&hasPhoto=${hasPhotoParam}`;
        }
        
        const response = await fetch(url);
        
        if (!response.ok) {
            throw new Error('Failed to fetch filtered students');
        }
        
        const data = await response.json();
        const students = data.students || [];
        
        console.log(`Loaded ${students.length} students with filter: ${filter}`);
        displayStudents(students);
        updatePhotoFilterCount(students.length, filter);
        
    } catch (error) {
        console.error('Error filtering students:', error);
        showMessage('Error filtering students: ' + error.message, 'error');
    }
}

function updatePhotoFilterCount(count = null, filter = null) {
    const countSpan = document.getElementById('photo-filter-count');
    
    if (count !== null && filter !== null) {
        let filterText = '';
        switch (filter) {
            case 'with-photos':
                filterText = 'with photos';
                break;
            case 'without-photos':
                filterText = 'without photos';
                break;
            default:
                filterText = 'total';
        }
        countSpan.textContent = `(${count} ${filterText})`;
    } else {
        // Count from current table
        const tableRows = document.querySelectorAll('#students-table tbody tr');
        const currentFilter = document.getElementById('photo-filter').value;
        
        let filterText = '';
        switch (currentFilter) {
            case 'with-photos':
                filterText = 'with photos';
                break;
            case 'without-photos':
                filterText = 'without photos';
                break;
            default:
                filterText = 'total';
        }
        
        countSpan.textContent = `(${tableRows.length} ${filterText})`;
    }
}

function displayStudentsTableLegacy2(students) { // superseded by the card renderer below
    // Try both possible tbody IDs for compatibility
    const tbody = document.getElementById('students-tbody') || document.querySelector('#students-table tbody');
    
    if (students.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 20px; color: #718096;">No students found with the current filter</td></tr>';
        return;
    }
    
    tbody.innerHTML = students.map(student => {
        const photoCell = student.hasPhoto && student.photoUrl
            ? `<img src="${student.photoUrl}" alt="${student.firstName} ${student.lastName}" style="width: 40px; height: 40px; border-radius: 50%; object-fit: cover; border: 2px solid #e2e8f0;">`
            : `<div style="width: 40px; height: 40px; border-radius: 50%; background: #f7fafc; border: 2px solid #e2e8f0; display: flex; align-items: center; justify-content: center; color: #a0aec0; font-size: 12px; font-weight: 600;">${student.firstName.charAt(0)}${student.lastName.charAt(0)}</div>`;
        
        const photoStatus = student.hasPhoto 
            ? '<span style="color: #22c55e; font-size: 12px;">✓ Has photo</span>'
            : '<span style="color: #ef4444; font-size: 12px;">✗ No photo</span>';
        
        return `
            <tr>
                <td style="text-align: center;">
                    ${photoCell}
                    <div style="margin-top: 4px;">${photoStatus}</div>
                </td>
                <td style="font-weight: 600;">${student.studentId}</td>
                <td>${student.firstName}</td>
                <td>${student.lastName}</td>
                <td style="color: #718096;">${student.email || 'N/A'}</td>
                <td>
                    <button class="btn" style="background: #ef4444; color: white; padding: 5px 10px; font-size: 12px;" onclick="deleteStudent('${student.id}', '${student.firstName}', '${student.lastName}')">Delete</button>
                </td>
            </tr>
        `;
    }).join('');
}

// Add animation styles
const styleSheet = document.createElement('style');
styleSheet.textContent = `
    @keyframes slideInUp {
        from {
            transform: translateY(100%);
            opacity: 0;
        }
        to {
            transform: translateY(0);
            opacity: 1;
        }
    }
`;
document.head.appendChild(styleSheet);

// Initialize when page loads
document.addEventListener('DOMContentLoaded', function() {
    // Always initialize the app - auth.js will handle showing login screen if needed
    initializeApp();
    
    // Set up auth check after a brief delay
    setTimeout(() => {
        if (window.isAuthenticated && !window.isAuthenticated()) {
            // User is not authenticated, auth.js should show login screen
            console.log('User not authenticated, login screen should be shown');
        } else if (window.isAuthenticated && window.isAuthenticated()) {
            // User is authenticated, make sure app is fully loaded
            console.log('User authenticated, app ready');
        }
    }, 500);
});

// Initialize the main application
function initializeApp() {
    // Always set up basic UI functionality first
    setupTabNavigation();
    setupDragAndDrop();
    
    // Load data (these will be called after authentication if needed)
    setTimeout(() => {
        if (window.isAuthenticated && window.isAuthenticated()) {
            loadAnalytics();
            loadArchivesList();
            loadArchiveHistory();
            checkForCompletedEvents();
        }
    }, 100);
}

// Set up tab navigation
function setupTabNavigation() {
    // Ensure tabs are clickable
    document.querySelectorAll('.tab').forEach(tab => {
        tab.style.pointerEvents = 'auto';
        tab.style.cursor = 'pointer';
    });
}

// Set up drag and drop
function setupDragAndDrop() {
    const uploadArea = document.querySelector('.upload-area');
    if (uploadArea) {
        uploadArea.addEventListener('dragleave', function(e) {
            e.currentTarget.classList.remove('dragover');
        });
    }
}


// ============================================================================
// Timestamp tolerance: Firestore emitted {seconds}; Cosmos stores ISO strings;
// scans store epoch ms. Every date read goes through here.
// ============================================================================
function tsToMillis(value) {
    if (!value) return 0;
    if (typeof value === 'number') return value < 1e12 ? value * 1000 : value;
    if (typeof value === 'object' && value.seconds != null) return value.seconds * 1000;
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
}

// ============================================================================
// Student cards — photo, identity, per-event attendance with SONIS export
// status, and manual add-to-event for administrators adding people in post.
// ============================================================================
function displayStudents(students) {
    const container = document.getElementById('students-cards');
    if (!container) return;

    if (!students || students.length === 0) {
        container.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 40px; color: #718096;">No students found.</div>';
        return;
    }

    container.innerHTML = students.map(student => {
        const initials = `${(student.firstName || '?').charAt(0)}${(student.lastName || '?').charAt(0)}`;
        const photo = (student.hasPhoto && student.photoUrl)
            ? `<img src="${student.photoUrl}" alt="" style="width: 72px; height: 72px; border-radius: 14px; object-fit: cover;">`
            : `<div style="width: 72px; height: 72px; border-radius: 14px; background: #e8edf7; display: flex; align-items: center; justify-content: center; color: #1e3c72; font-size: 24px; font-weight: 700;">${initials}</div>`;
        return `
            <div class="student-card" id="card-${student.studentId}" style="background: white; border: 2px solid #e2e8f0; border-radius: 14px; padding: 16px;">
                <div style="display: flex; gap: 14px; align-items: center;">
                    ${photo}
                    <div style="flex: 1; min-width: 0;">
                        <div style="font-weight: 700; font-size: 1.05rem; color: #2d3748;">${student.firstName || ''} ${student.lastName || ''}</div>
                        <div style="color: #4a5568; font-size: 0.85rem; font-weight: 600;">${student.studentId}</div>
                        <div style="color: #718096; font-size: 0.8rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${student.email || ''}</div>
                    </div>
                </div>
                <div style="display: flex; gap: 8px; margin-top: 12px;">
                    <button class="btn btn-secondary" style="flex: 1; padding: 7px; font-size: 0.82rem;"
                            onclick="toggleStudentAttendance('${student.studentId}')">Attendance</button>
                    <button class="btn btn-primary" style="flex: 1; padding: 7px; font-size: 0.82rem;"
                            onclick="showAddToEvent('${student.studentId}')">Add to Event</button>
                    <button class="btn" style="background: #fee2e2; color: #b91c1c; padding: 7px 10px; font-size: 0.82rem;"
                            onclick="deleteStudent('${student.id}', '${(student.firstName || '').replace(/'/g, "\\'")}', '${(student.lastName || '').replace(/'/g, "\\'")}')">✕</button>
                </div>
                <div id="attendance-${student.studentId}" style="display: none; margin-top: 12px; border-top: 1px solid #e2e8f0; padding-top: 10px;"></div>
                <div id="addevent-${student.studentId}" style="display: none; margin-top: 12px; border-top: 1px solid #e2e8f0; padding-top: 10px;"></div>
            </div>`;
    }).join('');
}

async function ensureEventsLoaded() {
    if (window.allEvents && window.allEvents.length) return window.allEvents;
    const snapshot = await db.collection('events').get();
    window.allEvents = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    return window.allEvents;
}

async function toggleStudentAttendance(studentId) {
    const panel = document.getElementById(`attendance-${studentId}`);
    if (!panel) return;
    if (panel.style.display !== 'none') { panel.style.display = 'none'; return; }
    panel.style.display = 'block';
    panel.innerHTML = '<div style="color: #718096; font-size: 0.85rem;">Loading attendance…</div>';

    try {
        const [events, scansSnapshot] = await Promise.all([
            ensureEventsLoaded(),
            db.collection('scans').where('studentId', '==', studentId).get(),
        ]);
        const eventById = Object.fromEntries(events.map(e => [e.id, e]));

        // One row per event, keeping the earliest scan time.
        const byEvent = new Map();
        scansSnapshot.docs.forEach(doc => {
            const scan = doc.data();
            const key = scan.listId || scan.eventId;
            if (!key) return;
            const t = tsToMillis(scan.timestamp);
            if (!byEvent.has(key) || t < byEvent.get(key)) byEvent.set(key, t);
        });

        if (byEvent.size === 0) {
            panel.innerHTML = '<div style="color: #718096; font-size: 0.85rem;">No attendance recorded.</div>';
            return;
        }

        // SONIS export status per event, from the export ledger.
        const rows = [];
        for (const [eventId, firstScan] of [...byEvent.entries()].sort((a, b) => b[1] - a[1])) {
            const event = eventById[eventId];
            const name = event ? `#${event.eventNumber} ${event.name}` : `(deleted event ${eventId.slice(0, 8)}…)`;
            let badge = '<span style="color: #b45309; background: #fef3c7; padding: 2px 8px; border-radius: 10px; font-size: 0.72rem; font-weight: 600;">Not in SONIS yet</span>';
            try {
                const ledger = await db.collection('sonis_exports').where('eventId', '==', eventId).get();
                const batches = ledger.docs.map(d => d.data())
                    .sort((a, b) => String(a.exportedAt).localeCompare(String(b.exportedAt)));
                const posted = new Set();
                for (const b of batches) {
                    for (const sid of (b.studentIds || [])) {
                        if (b.flag === '0') posted.delete(sid); else posted.add(sid);
                    }
                }
                if (posted.has(studentId)) {
                    badge = '<span style="color: #166534; background: #dcfce7; padding: 2px 8px; border-radius: 10px; font-size: 0.72rem; font-weight: 600;">✓ Exported to SONIS</span>';
                }
            } catch (e) { console.error('ledger check failed', e); }
            rows.push(`
                <div style="display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 5px 0; font-size: 0.82rem;">
                    <div style="min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                        ${name}
                        <span style="color: #a0aec0;"> · ${firstScan ? new Date(firstScan).toLocaleDateString() : ''}</span>
                    </div>
                    ${badge}
                </div>`);
        }
        panel.innerHTML = rows.join('');
    } catch (error) {
        console.error('Error loading attendance:', error);
        panel.innerHTML = '<div style="color: #b91c1c; font-size: 0.85rem;">Failed to load attendance.</div>';
    }
}

async function showAddToEvent(studentId) {
    const panel = document.getElementById(`addevent-${studentId}`);
    if (!panel) return;
    if (panel.style.display !== 'none') { panel.style.display = 'none'; return; }
    panel.style.display = 'block';
    panel.innerHTML = '<div style="color: #718096; font-size: 0.85rem;">Loading events…</div>';

    const events = (await ensureEventsLoaded())
        .filter(e => e.isActive !== false && !e.groupId)
        .sort((a, b) => tsToMillis(a.date) - tsToMillis(b.date));

    panel.innerHTML = `
        <div style="display: flex; gap: 8px; align-items: center;">
            <select id="addevent-select-${studentId}" style="flex: 1; padding: 7px; border: 2px solid #e2e8f0; border-radius: 8px; font-size: 0.82rem;">
                ${events.map(e => `<option value="${e.id}">#${e.eventNumber} ${e.name}</option>`).join('')}
            </select>
            <button class="btn btn-primary" style="padding: 7px 12px; font-size: 0.82rem;"
                    onclick="submitAddToEvent('${studentId}')">Add</button>
        </div>
        <div style="color: #a0aec0; font-size: 0.72rem; margin-top: 6px;">
            Records attendance exactly like a scan — the student gets the confirmation email if emails are enabled.
        </div>`;
}

async function submitAddToEvent(studentId) {
    const select = document.getElementById(`addevent-select-${studentId}`);
    if (!select || !select.value) return;
    const events = await ensureEventsLoaded();
    const event = events.find(e => e.id === select.value);
    if (!event) return;
    if (!confirm(`Mark ${studentId} as attending "#${event.eventNumber} ${event.name}"?`)) return;

    try {
        // Same endpoint the scanner uses: dual-structure write, student
        // enrichment, first-scan email — manual adds behave like real scans.
        await window.INSESSION_AZURE_DB.apiFetch('/addScanRecord', {
            method: 'POST',
            body: {
                id: 'admin-' + (crypto.randomUUID ? crypto.randomUUID() : Date.now() + '-' + Math.random().toString(36).slice(2)),
                eventId: event.id,
                code: studentId,
                studentId: studentId,
                timestamp: Date.now(),
                deviceId: 'admin_portal',
                symbology: 'MANUAL',
            },
        });
        showMessage(`Added ${studentId} to #${event.eventNumber} ${event.name}.`, 'success');
        const panel = document.getElementById(`addevent-${studentId}`);
        if (panel) panel.style.display = 'none';
        const att = document.getElementById(`attendance-${studentId}`);
        if (att && att.style.display !== 'none') { att.style.display = 'none'; toggleStudentAttendance(studentId); }
    } catch (error) {
        console.error('Manual add failed:', error);
        showMessage('Failed to add attendance: ' + error.message, 'error');
    }
}


// ============================================================================
// Group Scan Lists — prospect badge scanning (e.g. Admissions on iPads).
//
// These are NOT validated attendance lists: codes are prospective students or
// any other scanned QR badge. No roster lookup, no verified filter, no student
// identity — just deduplicated codes with first-scan time and an optional
// note. Export as CSV or email to the whole group.
// ============================================================================

window.userAccess = null;

async function fetchAccess() {
    try {
        window.userAccess = await window.INSESSION_AZURE_DB.apiFetch('/me');
    } catch (e) {
        console.error('access lookup failed', e);
        window.userAccess = null;
    }
    return window.userAccess;
}

// Full portal for admins and Student Affairs members; everyone else
// authorized (e.g. Admissions) sees only their group scan lists.
function applyAccessView() {
    const a = window.userAccess;
    if (!a) return;
    const fullAccess = a.isAdmin ||
        (a.groups || []).some(g => (g.name || '').toLowerCase() === 'student affairs');
    if (fullAccess) return;

    document.querySelectorAll('.tabs .tab').forEach(tab => {
        if (tab.id !== 'scanlists-tab-btn') tab.style.display = 'none';
    });
    document.querySelectorAll('.tab-pane').forEach(pane => pane.classList.remove('active'));
    document.getElementById('scanlists-tab').classList.add('active');
    document.getElementById('scanlists-tab-btn').classList.add('active');
    loadScanLists();
}

function myGroups() {
    return (window.userAccess && window.userAccess.groups) || [];
}

async function loadScanLists() {
    const container = document.getElementById('scanlists-container');
    if (!container) return;
    container.innerHTML = 'Loading…';
    try {
        if (!window.userAccess) await fetchAccess();
        const events = await ensureEventsLoaded();
        const groupIds = new Set(myGroups().map(g => g.id));
        const isAdmin = window.userAccess && window.userAccess.isAdmin;
        const lists = events
            .filter(e => e.groupId && (isAdmin || groupIds.has(e.groupId)))
            .sort((a, b) => tsToMillis(b.date) - tsToMillis(a.date));

        if (lists.length === 0) {
            container.innerHTML = '<div style="color: #718096; padding: 30px; text-align: center; background: #f7fafc; border-radius: 12px;">No scan lists yet. Create one to start scanning badges.</div>';
            return;
        }
        const groupName = (id) => (myGroups().find(g => g.id === id) || {}).name || 'group';
        container.innerHTML = lists.map(e => `
            <div style="background: white; border: 2px solid #e2e8f0; border-radius: 12px; padding: 16px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;"
                 onclick="openScanList('${e.id}')">
                <div>
                    <div style="font-weight: 700; color: #2d3748;">${e.name}</div>
                    <div style="color: #718096; font-size: 0.85rem;">
                        ${tsToMillis(e.date) ? new Date(tsToMillis(e.date)).toLocaleDateString(undefined, {timeZone:'UTC'}) : ''}
                        · ${groupName(e.groupId)}
                    </div>
                </div>
                <span style="color: #1e3c72; font-weight: 600;">Open →</span>
            </div>`).join('');
    } catch (e) {
        console.error(e);
        container.innerHTML = '<div style="color: #b91c1c;">Failed to load scan lists.</div>';
    }
}

async function createScanList() {
    if (!window.userAccess) await fetchAccess();
    const groups = myGroups();
    if (groups.length === 0) { showMessage('You are not in any group.', 'error'); return; }

    const name = prompt('Name for the new scan list (e.g. "Fall Open House 2026"):');
    if (!name || !name.trim()) return;
    let group = groups[0];
    if (groups.length > 1) {
        const pick = prompt('Which group? ' + groups.map((g, i) => `${i + 1}=${g.name}`).join('  '), '1');
        group = groups[Math.max(0, Math.min(groups.length - 1, (parseInt(pick) || 1) - 1))];
    }

    // Group scan lists live in a high number range so they can never collide
    // with SONIS attendance event ids (5xx).
    const events = await ensureEventsLoaded();
    const next = Math.max(9000, ...events.map(e => Number(e.eventNumber) || 0).filter(n => n >= 9000)) + 1;

    try {
        await window.INSESSION_AZURE_DB.apiFetch('/createEvent', {
            method: 'POST',
            body: {
                name: name.trim(),
                eventNumber: next,
                date: new Date().toISOString(),
                groupId: group.id,
                createdBy: (window.userAccess && window.userAccess.upn) || 'portal',
            },
        });
        window.allEvents = null; // refresh cache
        showMessage(`Scan list "${name.trim()}" created for ${group.name}.`, 'success');
        loadScanLists();
    } catch (e) {
        console.error(e);
        showMessage('Failed to create scan list: ' + e.message, 'error');
    }
}

let scanListNoteDocs = {};

async function openScanList(eventId) {
    const detail = document.getElementById('scanlist-detail');
    detail.style.display = 'block';
    detail.innerHTML = '<div style="color: #718096;">Loading scans…</div>';

    try {
        const events = await ensureEventsLoaded();
        const event = events.find(e => e.id === eventId);

        const [flatSnap, nestedSnap] = await Promise.all([
            db.collection('scans').where('listId', '==', eventId).get(),
            db.collection('lists').doc(eventId).collection('scans').get(),
        ]);

        // Dedup by CODE — every badge counts once, no validation of any kind.
        const byCode = new Map();
        scanListNoteDocs = {};
        const consider = (doc, source) => {
            const scan = doc.data();
            const code = String(scan.code || '').trim();
            if (!code) return;
            const t = tsToMillis(scan.timestamp);
            const existing = byCode.get(code);
            if (!existing || t < existing.t) {
                byCode.set(code, { t, note: scan.note || (existing && existing.note) || '', docId: doc.id, source });
            } else if (!existing.note && scan.note) {
                existing.note = scan.note;
            }
        };
        flatSnap.docs.forEach(d => consider(d, 'flat'));
        nestedSnap.docs.forEach(d => consider(d, 'nested'));

        const rows = [...byCode.entries()].sort((a, b) => b[1].t - a[1].t);
        rows.forEach(([code, info]) => { scanListNoteDocs[code] = info; });

        detail.innerHTML = `
            <div style="background: white; border: 2px solid #e2e8f0; border-radius: 12px; padding: 20px;">
                <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 16px;">
                    <div>
                        <h3 style="color: #2d3748; margin: 0;">${event ? event.name : 'Scan list'}</h3>
                        <div style="color: #718096; font-size: 0.85rem;">${rows.length} unique badge${rows.length === 1 ? '' : 's'} scanned</div>
                    </div>
                    <div style="display: flex; gap: 8px;">
                        <button class="btn btn-secondary" onclick="exportScanListCSV('${eventId}')">Export CSV</button>
                        <button class="btn btn-primary" onclick="emailScanList('${eventId}', '${event ? event.groupId : ''}')">Email to Group</button>
                    </div>
                </div>
                ${rows.length === 0 ? '<div style="color: #718096; padding: 20px; text-align: center;">No scans yet.</div>' : `
                <table style="width: 100%; border-collapse: collapse; font-size: 0.9rem;">
                    <thead><tr style="text-align: left; color: #4a5568; border-bottom: 2px solid #e2e8f0;">
                        <th style="padding: 8px;">Badge / QR Code</th>
                        <th style="padding: 8px;">First Scanned</th>
                        <th style="padding: 8px; width: 40%;">Note</th>
                    </tr></thead>
                    <tbody>
                        ${rows.map(([code, info]) => `
                        <tr style="border-bottom: 1px solid #edf2f7;">
                            <td style="padding: 8px; font-weight: 600;">${code}</td>
                            <td style="padding: 8px; color: #718096;">${info.t ? new Date(info.t).toLocaleString() : ''}</td>
                            <td style="padding: 8px;">
                                <input type="text" value="${(info.note || '').replace(/"/g, '&quot;')}"
                                       placeholder="Add a note…"
                                       style="width: 100%; padding: 6px 8px; border: 1px solid #e2e8f0; border-radius: 6px; font-size: 0.85rem;"
                                       onchange="saveScanNote('${eventId}', '${code.replace(/'/g, "\\'")}', this.value)">
                            </td>
                        </tr>`).join('')}
                    </tbody>
                </table>`}
            </div>`;
        detail.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) {
        console.error(e);
        detail.innerHTML = '<div style="color: #b91c1c;">Failed to load scans.</div>';
    }
}

async function saveScanNote(eventId, code, note) {
    try {
        const info = scanListNoteDocs[code];
        if (!info) return;
        if (info.source === 'flat') {
            await db.collection('scans').doc(info.docId).update({ note: note });
        } else {
            await db.collection('lists').doc(eventId).collection('scans').doc(info.docId).update({ note: note });
        }
        info.note = note;
        showMessage('Note saved.', 'success');
    } catch (e) {
        console.error(e);
        showMessage('Failed to save note: ' + e.message, 'error');
    }
}

function exportScanListCSV(eventId) {
    const rows = Object.entries(scanListNoteDocs)
        .sort((a, b) => a[1].t - b[1].t);
    const esc = (v) => /[",\n]/.test(String(v)) ? `"${String(v).replace(/"/g, '""')}"` : String(v);
    const csv = ['code,scannedAt,note',
        ...rows.map(([code, info]) =>
            [code, info.t ? new Date(info.t).toISOString() : '', info.note || ''].map(esc).join(','))
    ].join('\r\n') + '\r\n';
    const today = new Date();
    const stamp = `${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}${String(today.getDate()).padStart(2, '0')}`;
    downloadTextFile(csv, `scan_list_${stamp}.csv`);
}

async function emailScanList(eventId, groupId) {
    if (!groupId) { showMessage('This list has no group.', 'error'); return; }
    if (!confirm('Email the current scan list to every member of the group?')) return;
    try {
        const result = await window.INSESSION_AZURE_DB.apiFetch('/emailEventReport', {
            method: 'POST',
            body: { eventId: eventId, groupId: groupId },
        });
        showMessage(`Sent to ${result.recipients.length} group member${result.recipients.length === 1 ? '' : 's'}.`, 'success');
    } catch (e) {
        console.error(e);
        showMessage('Failed to send: ' + e.message, 'error');
    }
}

// Load scan lists when the tab is opened, and gate the portal by access level
// once sign-in completes.
(function () {
    const origShowTab = window.showTab;
    window.showTab = function (tabName) {
        origShowTab(tabName);
        if (tabName === 'scanlists') loadScanLists();
    };
    const origInit = window.initializeApp;
    window.initializeApp = function () {
        if (origInit) origInit();
        setTimeout(async () => {
            await fetchAccess();
            applyAccessView();
        }, 300);
    };
})();
