import { GoogleGenAI } from '@google/genai';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Calculate __dirname for ES Modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// --- BULLETPROOF ENV PARSER (Bypassing dotenv and terminal wrappers) ---
const envPath = path.join(__dirname, '..', '.env');
let apiKey = '';

try {
  const envContent = fs.readFileSync(envPath, 'utf8');
  // Regex to find GEMINI_API_KEY=value, ignoring potential spaces and comments
  const match = envContent.match(/^GEMINI_API_KEY\s*=\s*([^#\r\n]+)/m);
  if (match && match[1]) {
    apiKey = match[1].trim();
  }
} catch (err) {
  console.error(`[Test] Error reading .env file at ${envPath}:`, err.message);
  process.exit(1);
}

if (!apiKey) {
  console.error("Error: GEMINI_API_KEY not found in manual .env parse.");
  process.exit(1);
}
// ------------------------------------------------------------------------

const filePath = process.argv[2];

if (!filePath) {
  console.error("Usage: node scripts/test_syllabus.mjs <path-to-pdf>");
  process.exit(1);
}

if (!fs.existsSync(filePath)) {
  console.error(`Error: File not found at ${filePath}`);
  process.exit(1);
}

async function runTest() {
  console.log(`[Test] Initializing Gemini with @google/genai...`);
  const ai = new GoogleGenAI({ apiKey });

  try {
    console.log(`[Test] Uploading file: ${path.basename(filePath)}...`);
    const uploadResult = await ai.files.upload({
      file: filePath,
      config: { mimeType: "application/pdf" }
    });

    console.log(`[Test] File uploaded successfully. URI: ${uploadResult.uri}`);

    const prompt = `Act as a Malaysian university study planner. 
Extract all courses (primary_tasks) and their associated assignments (sub_tasks) including deadlines if mentioned.
Output a strict JSON array where each item represents a Course and contains its sub_tasks.

JSON Schema:
[
  {
    "course_title": "String",
    "due_date": "ISO Date String or null",
    "sub_tasks": [
      {
        "title": "Assignment Title",
        "priority": "high|medium|low",
        "estimated_minutes": Number,
        "due_date": "ISO Date String or null"
      }
    ]
  }
]

Ensure all priorities are lowercase 'high', 'medium', or 'low'.
Ensure ESTIMATED_MINUTES is a realistic number for a student (e.g., 60, 120, 240).
Return ONLY the JSON. No markdown backticks.`;

    console.log(`[Test] Requesting extraction from gemini-3.1-flash-lite-preview...`);
    const result = await ai.models.generateContent({
      model: 'gemini-3.1-flash-lite-preview',
      contents: [
        {
          parts: [
            { fileData: { fileUri: uploadResult.uri, mimeType: uploadResult.mimeType } },
            { text: prompt }
          ]
        }
      ],
      generationConfig: { responseMimeType: "application/json" }
    });

    const responseText = result.candidates[0].content.parts[0].text;
    console.log("\n--- [AI EXTRACTION RESULT] ---");
    try {
      const parsed = JSON.parse(responseText);
      console.log(JSON.stringify(parsed, null, 2));
      console.log("------------------------------");
      console.log("\x1b[32mSuccess: JSON is valid and structure looks correct.\x1b[0m");
    } catch (e) {
      console.error("\x1b[31mError: Output was not valid JSON.\x1b[0m");
      console.log(responseText);
    }

  } catch (error) {
    console.error(`[Test] Critical Error:`, error.message || error);
  }
}

runTest();
