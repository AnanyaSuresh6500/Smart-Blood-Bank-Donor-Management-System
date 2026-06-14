/**
 * Smart Blood Bank — Seed Script
 * Imports Kaggle donor data + generates hospitals and blood requests
 * Run with: node database/seed.js
 */

require('dotenv').config({ path: './backend/.env' });
const { Pool } = require('pg');
const { faker } = require('@faker-js/faker');
const fs = require('fs');
const path = require('path');
const { parse } = require('csv-parse/sync');

const pool = new Pool({
  host:     process.env.DB_HOST,
  port:     process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user:     process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

// ── Helpers ───────────────────────────────────────────────
const readCSV = (filename) => {
  const filePath = path.join(__dirname, 'data', filename);
  const content = fs.readFileSync(filePath, 'utf-8');
  return parse(content, { columns: true, skip_empty_lines: true });
};

const randomBetween = (min, max) =>
  Math.floor(Math.random() * (max - min + 1)) + min;

const randomDate = (start, end) =>
  new Date(start.getTime() + Math.random() * (end.getTime() - start.getTime()));

const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const URGENCY_LEVELS = ['routine', 'urgent', 'critical'];

// ── Step 1: Clear existing data ───────────────────────────
async function clearData(client) {
  console.log('🗑️  Clearing existing data...');
  await client.query(`
    TRUNCATE TABLE AuditLog, RequestApprovals, BloodRequests,
    BloodInventory, Donations, DonorEligibility,
    Hospitals, Donors, Users
    RESTART IDENTITY CASCADE
  `);
  console.log('✅ Data cleared');
}

// ── Step 2: Create admin user ─────────────────────────────
async function seedAdmin(client) {
  console.log('👤 Creating admin user...');
  const bcrypt = require('bcrypt');
  const hash = await bcrypt.hash('admin123', 12);

  await client.query(`
    INSERT INTO Users (email, password_hash, role, active)
    VALUES ($1, $2, 'admin', true)
  `, ['admin@bloodbank.com', hash]);

  console.log('✅ Admin created — email: admin@bloodbank.com password: admin123');
}

// ── Step 3: Seed hospitals ────────────────────────────────
async function seedHospitals(client) {
  console.log('🏥 Seeding 20 hospitals...');
  const hospitals = [];

  for (let i = 0; i < 20; i++) {
    const name = `${faker.location.city()} ${faker.helpers.arrayElement([
      'General Hospital', 'Medical Centre', 'Blood Centre',
      'Regional Hospital', 'Community Hospital'
    ])}`;

    const result = await client.query(`
      INSERT INTO Hospitals (name, registration_number, contact_email, contact_phone, address, approved)
      VALUES ($1, $2, $3, $4, $5, true)
      RETURNING hospital_id
    `, [
      name,
      `HOSP-${String(i + 1).padStart(6, '0')}`,
      faker.internet.email().toLowerCase(),
      `+1${faker.string.numeric(10)}`,
      faker.location.streetAddress(),
    ]);

    // Create a hospital staff user for each hospital
    const bcrypt = require('bcrypt');
    const hash = await bcrypt.hash('hospital123', 12);
    await client.query(`
      INSERT INTO Users (email, password_hash, role, hospital_id, active)
      VALUES ($1, $2, 'hospital_staff', $3, true)
    `, [
      `staff${i + 1}@bloodbank.com`,
      hash,
      result.rows[0].hospital_id
    ]);

    hospitals.push(result.rows[0].hospital_id);
  }

  console.log('✅ 20 hospitals seeded');
  return hospitals;
}

// ── Step 4: Seed donors from Kaggle data ──────────────────
async function seedDonors(client) {
  console.log('🩸 Seeding donors from Kaggle dataset...');
  const records = readCSV('blood_donation_registry_ml_ready.csv');

  // Use first 500 records
  const sample = records.slice(0, 500);
  const donorIds = [];
  const bcrypt = require('bcrypt');
  const hash = await bcrypt.hash('donor123', 12);

  for (let i = 0; i < sample.length; i++) {
    const record = sample[i];

    // Create user account for donor
    const userResult = await client.query(`
      INSERT INTO Users (email, password_hash, role, active)
      VALUES ($1, $2, 'donor', true)
      RETURNING user_id
    `, [
      `donor${i + 1}@bloodbank.com`,
      hash
    ]);

    const userId = userResult.rows[0].user_id;

    // Calculate date of birth from age
    const dob = new Date();
    dob.setFullYear(dob.getFullYear() - parseInt(record.age));

    // Insert donor
    const donorResult = await client.query(`
      INSERT INTO Donors (
        user_id, first_name, last_name, blood_group,
        date_of_birth, gender, contact_phone, address, active
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true)
      RETURNING donor_id
    `, [
      userId,
      faker.person.firstName(record.sex === 'M' ? 'male' : 'female'),
      faker.person.lastName(),
      record.blood_type,
      dob.toISOString().split('T')[0],
      record.sex === 'M' ? 'male' : 'female',
      `+1${faker.string.numeric(10)}`,
      faker.location.streetAddress(),
    ]);

    const donorId = donorResult.rows[0].donor_id;
    donorIds.push({ donorId, record });

    // Insert eligibility status from Kaggle data
    const lastDonation = record.last_donation_date || null;
    const deferralUntil = record.eligibility_status === 'temporary_deferral' && lastDonation
      ? new Date(new Date(lastDonation).getTime() + 56 * 24 * 60 * 60 * 1000)
        .toISOString().split('T')[0]
      : null;

    await client.query(`
      INSERT INTO DonorEligibility (
        donor_id, eligible, last_donation_date,
        deferral_reason, deferral_until, eligibility_status
      )
      VALUES ($1, $2, $3, $4, $5, $6)
    `, [
      donorId,
      record.eligible_to_donate === '1',
      lastDonation,
      record.deferral_reason || null,
      deferralUntil,
      record.eligibility_status,
    ]);

    if ((i + 1) % 100 === 0) console.log(`   ${i + 1}/500 donors inserted`);
  }

  console.log('✅ 500 donors seeded from Kaggle data');
  return donorIds;
}

// ── Step 5: Seed donations ────────────────────────────────
async function seedDonations(client, donorData) {
  console.log('💉 Seeding donations...');
  let count = 0;

  for (const { donorId, record } of donorData) {
    const donationCount = parseInt(record.lifetime_donation_count) || 0;
    // Generate up to 5 historical donations per donor
    const toGenerate = Math.min(donationCount, 5);

    for (let i = 0; i < toGenerate; i++) {
      const donationDate = randomDate(
        new Date('2023-01-01'),
        new Date('2024-12-31')
      );

      await client.query(`
        INSERT INTO Donations (
          donor_id, donation_date, blood_group,
          volume_ml, donation_centre, status
        )
        VALUES ($1, $2, $3, $4, $5, 'completed')
      `, [
        donorId,
        donationDate.toISOString().split('T')[0],
        record.blood_type,
        randomBetween(350, 450),
        faker.helpers.arrayElement([
          'City Blood Centre', 'General Hospital', 'Mobile Unit',
          'Community Camp', 'Regional Medical Centre'
        ]),
      ]);
      count++;
    }
  }

  console.log(`✅ ${count} donations seeded`);
}

// ── Step 6: Seed blood inventory ──────────────────────────
async function seedInventory(client) {
  console.log('🏦 Seeding blood inventory...');

  const inventoryLevels = {
    'O+': 45, 'O-': 12, 'A+': 38, 'A-': 10,
    'B+': 22, 'B-': 8,  'AB+': 15, 'AB-': 5
  };

  for (const [bloodGroup, units] of Object.entries(inventoryLevels)) {
    await client.query(`
      INSERT INTO BloodInventory (blood_group, units_available, last_updated)
      VALUES ($1, $2, NOW())
    `, [bloodGroup, units]);
  }

  console.log('✅ Blood inventory seeded');
}

// ── Step 7: Seed blood requests ───────────────────────────
async function seedRequests(client, hospitalIds) {
  console.log('📋 Seeding 1800 blood requests...');

  const statuses = ['fulfilled', 'fulfilled', 'fulfilled', 'rejected', 'approved'];

  for (let i = 0; i < 1800; i++) {
    const requestDate = randomDate(
      new Date('2024-01-01'),
      new Date('2024-12-31')
    );

    const status = faker.helpers.arrayElement(statuses);
    const fulfilledAt = status === 'fulfilled'
      ? new Date(requestDate.getTime() + randomBetween(1, 72) * 60 * 60 * 1000)
      : null;

    await client.query(`
      INSERT INTO BloodRequests (
        hospital_id, blood_group, units_required,
        urgency, status, requested_at, fulfilled_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, [
      faker.helpers.arrayElement(hospitalIds),
      faker.helpers.arrayElement(BLOOD_GROUPS),
      randomBetween(1, 10),
      faker.helpers.arrayElement(URGENCY_LEVELS),
      status,
      requestDate.toISOString(),
      fulfilledAt ? fulfilledAt.toISOString() : null,
    ]);

    if ((i + 1) % 300 === 0) console.log(`   ${i + 1}/1800 requests inserted`);
  }

  console.log('✅ 1800 blood requests seeded');
}

// ── Step 8: Update compatibility.json ─────────────────────
async function updateCompatibility() {
  console.log('🔄 Updating compatibility.json from Kaggle data...');
  const records = readCSV('blood_compatibility_lookup.csv');

  const matrix = {};
  for (const record of records) {
    if (record.compatible_for_rbc_transfusion === '1') {
      if (!matrix[record.recipient_blood_type]) {
        matrix[record.recipient_blood_type] = [];
      }
      matrix[record.recipient_blood_type].push({
        donor: record.donor_blood_type,
        level: record.compatibility_level
      });
    }
  }

  fs.writeFileSync(
    path.join(__dirname, '../ai-service/compatibility.json'),
    JSON.stringify(matrix, null, 2)
  );
  console.log('✅ compatibility.json updated with Kaggle compatibility data');
}

// ── Main ──────────────────────────────────────────────────
async function main() {
  const client = await pool.connect();

  try {
    console.log('\n🚀 Starting seed process...\n');
    await client.query('BEGIN');

    await clearData(client);
    await seedAdmin(client);
    const hospitalIds = await seedHospitals(client);
    const donorData = await seedDonors(client);
    await seedDonations(client, donorData);
    await seedInventory(client);
    await seedRequests(client, hospitalIds);

    await client.query('COMMIT');
    console.log('\n✅ All data seeded successfully!\n');
    console.log('Login credentials:');
    console.log('  Admin:    admin@bloodbank.com    / admin123');
    console.log('  Donors:   donor1@bloodbank.com   / donor123');
    console.log('  Hospital: staff1@bloodbank.com   / hospital123\n');

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Seed failed, rolling back:', err.message);
    console.error(err);
  } finally {
    client.release();
    await pool.end();
  }
}

// Update compatibility.json then run main seed
updateCompatibility().then(() => main());