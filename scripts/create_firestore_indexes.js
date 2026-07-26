/**
 * Firebase Admin Script to Auto-Create Firestore Indexes
 * 
 * Run this script to automatically create all required Firestore indexes
 * 
 * Setup:
 * 1. Install Firebase Admin SDK: npm install firebase-admin
 * 2. Get your service account key from Firebase Console
 * 3. Set GOOGLE_APPLICATION_CREDENTIALS environment variable
 * 
 * Usage:
 * node scripts/create_firestore_indexes.js
 */

const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin
// Option 1: Use service account key file
// const serviceAccount = require('./path/to/serviceAccountKey.json');
// admin.initializeApp({
//   credential: admin.credential.cert(serviceAccount)
// });

// Option 2: Use environment variable (recommended)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Required indexes for the attendance app
 */
const requiredIndexes = [
  {
    collectionGroup: 'inOut',
    fields: [
      { fieldPath: 'instituteCode', order: 'ASCENDING' }
    ],
    queryScope: 'COLLECTION_GROUP'
  },
  {
    collectionGroup: 'inOut',
    fields: [
      { fieldPath: 'instituteCode', order: 'ASCENDING' },
      { fieldPath: 'date', order: 'ASCENDING' }
    ],
    queryScope: 'COLLECTION_GROUP'
  },
  {
    collectionGroup: 'inOut',
    fields: [
      { fieldPath: 'instituteCode', order: 'ASCENDING' },
      { fieldPath: 'studentId', order: 'ASCENDING' }
    ],
    queryScope: 'COLLECTION_GROUP'
  },
  {
    collectionGroup: 'inOut',
    fields: [
      { fieldPath: 'instituteCode', order: 'ASCENDING' },
      { fieldPath: 'date', order: 'ASCENDING' },
      { fieldPath: 'type', order: 'ASCENDING' }
    ],
    queryScope: 'COLLECTION_GROUP'
  },
  {
    collectionGroup: 'inOut',
    fields: [
      { fieldPath: 'instituteCode', order: 'ASCENDING' },
      { fieldPath: 'studentId', order: 'ASCENDING' },
      { fieldPath: 'date', order: 'ASCENDING' }
    ],
    queryScope: 'COLLECTION_GROUP'
  }
];

/**
 * Create a Firestore index
 */
async function createIndex(indexConfig) {
  try {
    const indexName = `${indexConfig.collectionGroup}_${indexConfig.fields.map(f => f.fieldPath).join('_')}`;
    
    console.log(`Creating index: ${indexName}...`);
    
    // Note: Firestore Admin SDK doesn't have direct index creation API
    // We need to use the REST API or firestore.indexes.json file
    
    // For now, we'll generate the firestore.indexes.json content
    const indexDefinition = {
      collectionGroup: indexConfig.collectionGroup,
      queryScope: indexConfig.queryScope,
      fields: indexConfig.fields
    };
    
    console.log(`✅ Index definition prepared: ${indexName}`);
    console.log(JSON.stringify(indexDefinition, null, 2));
    
    return indexDefinition;
  } catch (error) {
    console.error(`❌ Error creating index: ${error.message}`);
    throw error;
  }
}

/**
 * Generate firestore.indexes.json file
 */
function generateIndexesFile() {
  const indexes = {
    indexes: requiredIndexes.map(index => ({
      collectionGroup: index.collectionGroup,
      queryScope: index.queryScope,
      fields: index.fields
    })),
    fieldOverrides: []
  };
  
  return JSON.stringify(indexes, null, 2);
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Starting Firestore index creation...\n');
  
  try {
    // Generate indexes file
    const indexesJson = generateIndexesFile();
    
    // Write to firestore.indexes.json
    const fs = require('fs');
    const indexPath = path.join(__dirname, '..', 'firestore.indexes.json');
    fs.writeFileSync(indexPath, indexesJson);
    
    console.log('✅ Generated firestore.indexes.json');
    console.log('\n📋 Next steps:');
    console.log('1. Review firestore.indexes.json');
    console.log('2. Run: firebase deploy --only firestore:indexes');
    console.log('3. Wait for indexes to be created (may take a few minutes)');
    console.log('\nOr use the Firebase Console links from error messages to create indexes automatically.\n');
    
    // Also print individual index definitions
    console.log('📝 Index Definitions:\n');
    for (const index of requiredIndexes) {
      await createIndex(index);
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = { createIndex, generateIndexesFile, requiredIndexes };
