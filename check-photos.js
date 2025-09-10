#!/usr/bin/env node

/**
 * Student Photo Checker Script
 * 
 * This script calls the Firebase Function to check and update student photos
 * from Firebase Storage using the convention: {Student ID}-photo.jpg
 * 
 * Usage:
 *   node check-photos.js
 *   node check-photos.js --details  (to see individual student results)
 */

const https = require('https');

const FUNCTION_URL = 'https://us-central1-scannerappfb.cloudfunctions.net/checkStudentPhotos';

function makeRequest(url, includeDetails = false) {
    const requestUrl = includeDetails ? `${url}?includeDetails=true` : url;
    
    console.log('🔍 Checking student photos in Firebase Storage...\n');
    
    return new Promise((resolve, reject) => {
        const req = https.get(requestUrl, (res) => {
            let data = '';
            
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                try {
                    const result = JSON.parse(data);
                    resolve(result);
                } catch (e) {
                    reject(new Error('Failed to parse response: ' + e.message));
                }
            });
        });
        
        req.on('error', (error) => {
            reject(error);
        });
        
        req.setTimeout(30000, () => {
            req.destroy();
            reject(new Error('Request timeout'));
        });
    });
}

async function main() {
    try {
        const includeDetails = process.argv.includes('--details');
        const result = await makeRequest(FUNCTION_URL, includeDetails);
        
        if (result.success) {
            const summary = result.summary;
            
            console.log('✅ Photo check completed successfully!\n');
            console.log('📊 Summary:');
            console.log(`   Total students: ${summary.totalStudents}`);
            console.log(`   Photos found: ${summary.photosFound}`);
            console.log(`   Photos not found: ${summary.photosNotFound}`);
            console.log(`   Records updated: ${summary.recordsUpdated}`);
            console.log(`   Timestamp: ${summary.timestamp}\n`);
            
            if (includeDetails && result.results) {
                console.log('📋 Detailed Results:\n');
                
                const withPhotos = result.results.filter(r => r.hasPhoto);
                const withoutPhotos = result.results.filter(r => !r.hasPhoto);
                
                if (withPhotos.length > 0) {
                    console.log(`✅ Students WITH photos (${withPhotos.length}):`);
                    withPhotos.forEach(student => {
                        console.log(`   ${student.studentId} - ${student.name}`);
                    });
                    console.log('');
                }
                
                if (withoutPhotos.length > 0) {
                    console.log(`❌ Students WITHOUT photos (${withoutPhotos.length}):`);
                    withoutPhotos.forEach(student => {
                        console.log(`   ${student.studentId} - ${student.name} (expected: ${student.expectedFileName})`);
                    });
                    console.log('');
                }
            }
            
            console.log('💡 Tips:');
            console.log('   - Upload photos to Firebase Storage with naming convention: {StudentID}-photo.jpg');
            console.log('   - Photos are automatically linked to student records');
            console.log('   - Use the admin portal filter to find students without photos');
            console.log('   - Run this script again after uploading new photos');
            
        } else {
            console.error('❌ Photo check failed:', result.error || 'Unknown error');
            process.exit(1);
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Show usage if help is requested
if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log('Student Photo Checker\n');
    console.log('Usage:');
    console.log('  node check-photos.js          Check photos and show summary');
    console.log('  node check-photos.js --details Show detailed results for each student');
    console.log('  node check-photos.js --help   Show this help message\n');
    console.log('This script checks Firebase Storage for student photos using the naming');
    console.log('convention {StudentID}-photo.jpg and updates the student records.');
    process.exit(0);
}

main();