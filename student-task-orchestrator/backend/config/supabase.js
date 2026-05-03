import { createClient } from '@supabase/supabase-js';
import { AsyncLocalStorage } from 'node:async_hooks';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../.env'), override: true });
console.log("Loaded Supabase URL:", "'" + process.env.SUPABASE_URL + "'");

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseAnonKey || !supabaseKey) {
  throw new Error('Supabase URL, Anon Key, and Service Role Key must be provided in .env');
}

// Service role client for backend/background operations.
const serviceSupabase = createClient(supabaseUrl, supabaseKey);
const supabaseContext = new AsyncLocalStorage();

export const getCurrentSupabase = () => supabaseContext.getStore() ?? serviceSupabase;

export const runWithSupabase = (client, callback) => {
  supabaseContext.run(client, callback);
};

export const supabase = new Proxy(serviceSupabase, {
  get(target, prop) {
    const client = getCurrentSupabase();
    const value = Reflect.get(client, prop, client);
    return typeof value === 'function' ? value.bind(client) : value;
  },
  set(target, prop, value) {
    return Reflect.set(target, prop, value, target);
  }
});

export const createSupabaseForToken = (token) =>
  createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false
    },
    global: {
      headers: {
        Authorization: `Bearer ${token}`
      }
    }
  });
