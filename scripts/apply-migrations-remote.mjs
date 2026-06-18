import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');

const client = new pg.Client({
  host: process.env.SUPABASE_DB_HOST ?? 'db.zmdokvjewvqaftnvulsr.supabase.co',
  port: Number(process.env.SUPABASE_DB_PORT ?? 5432),
  database: process.env.SUPABASE_DB_NAME ?? 'postgres',
  user: process.env.SUPABASE_DB_USER ?? 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: { rejectUnauthorized: false },
});

const migrations = [
  '001_extensions.sql',
  '002_enums.sql',
  '010_roles.sql',
  '011_company.sql',
  '012_user.sql',
  '013_account.sql',
];

async function main() {
  if (!process.env.SUPABASE_DB_PASSWORD) {
    console.error('Falta SUPABASE_DB_PASSWORD');
    process.exit(1);
  }

  await client.connect();
  console.log('Conectado a Supabase Postgres');

  for (const file of migrations) {
    const sql = fs.readFileSync(path.join(root, 'migrations', file), 'utf8');
    console.log(`Aplicando ${file}...`);
    await client.query(sql);
    console.log(`  OK`);
  }

  const { rows: tables } = await client.query(`
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('rol', 'empresa', 'usuario', 'cuenta')
    ORDER BY table_name
  `);
  const { rows: [{ roles }] } = await client.query('SELECT COUNT(*)::int AS roles FROM rol');

  console.log('\nTablas creadas:', tables.map((r) => r.table_name).join(', '));
  console.log('Roles sembrados:', roles);

  await client.end();
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
