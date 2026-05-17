import { supabase } from '../config/supabase.js';
import csv from 'csv-parser';
import { Readable } from 'stream';

const PRIORITY_SCORES = {
  high: 90,
  medium: 60,
  low: 30
};

export const importTasksFromCsv = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: "No file uploaded" });
    }

    const userId = req.user.id;
    // 1. Define masterRows array outside the stream to accumulate all data safely
    const masterRows = [];
    
    // Parse CSV from buffer
    const stream = Readable.from(req.file.buffer.toString());
    
    await new Promise((resolve, reject) => {
      stream
        .pipe(csv({ 
          mapHeaders: ({ header }) => header.trim(),
          stripBOM: true 
        }))
        .on('data', (data) => {
          // 2. STRICT DEEP CLONE: Break all references to internal parser object pools.
          // This prevents every row in the array from being overwritten by the last row.
          masterRows.push(JSON.parse(JSON.stringify(data)));
        })
        .on('end', resolve)
        .on('error', reject);
    });

    // 3. DIAGNOSTIC LOG: Verify the array size immediately after parsing
    console.log('--- CSV IMPORT DIAGNOSTIC ---');
    console.log('Total Rows Parsed:', masterRows.length);

    if (masterRows.length === 0) {
      return res.status(400).json({ error: "CSV file is empty or invalid" });
    }

    // Grouping logic: Group rows by 'Course' (Case-Insensitive)
    const courseGroups = {};
    
    masterRows.forEach((row, index) => {
      // DEBUG: Inspect raw CSV row to identify header naming issues
      console.log(`[DEBUG] Raw Row ${index + 1}:`, row);

      // UTILITY: Find value by case-insensitive AND trim-safe key search
      const getValue = (keyName) => {
        const foundKey = Object.keys(row).find(k => k.trim().toLowerCase() === keyName.toLowerCase());
        const val = foundKey ? row[foundKey] : '';
        return (val === null || val === undefined) ? '' : val.toString().trim();
      };

      const rawCourse = getValue('Course');
      const courseTitle = rawCourse;
      
      const normalizedKey = courseTitle.toLowerCase().replace(/\s+/g, ' ').trim();
      const taskTitle = getValue('Task Title');
      
      if (!normalizedKey) {
        console.warn(`Row ${index + 1} skipped: Missing Course Title`);
        return;
      }
      
      const rawDate = getValue('Due Date');
      
      if (!courseGroups[normalizedKey]) {
        courseGroups[normalizedKey] = {
          displayTitle: courseTitle, 
          dueDate: rawDate || null,
          subTasks: []
        };
      }
      
      if (taskTitle) {
        // PRIORITY LOGIC: Use robust getValue helper and normalize
        const rawPriority = getValue('Priority').toLowerCase();
        const validPriorities = ['high', 'medium', 'low'];
        const priority = validPriorities.includes(rawPriority) ? rawPriority : 'low';

        courseGroups[normalizedKey].subTasks.push({
          title: taskTitle,
          estimated_minutes: parseInt(getValue('Estimated Minutes')) || 0,
          priority: priority
        });
      }
    });

    console.log('Normalized unique courses found:', Object.keys(courseGroups).length);

    const results = [];

    // Process each course group sequentially for safety
    for (const key of Object.keys(courseGroups)) {
      const group = courseGroups[key];
      const title = group.displayTitle;

      // Step 1: Find or Create Primary Task (Case-Insensitive Database Match)
      let { data: existingTasks, error: fetchError } = await supabase
        .from('primary_tasks')
        .select('id, title')
        .eq('user_id', userId)
        .ilike('title', title); // Use ILIKE for case-insensitive match in Postgres

      if (fetchError) throw fetchError;

      // Check if any of the existing tasks match our normalized criteria
      const existingTask = existingTasks.find(t => 
        t.title.toLowerCase().replace(/\s+/g, ' ').trim() === key
      );

      if (fetchError) throw fetchError;

      let primaryTaskId;
      if (existingTask) {
        primaryTaskId = existingTask.id;
      } else {
        let isoDate = null;
        if (group.dueDate) {
          const dateObj = new Date(group.dueDate);
          if (!isNaN(dateObj.getTime())) {
            isoDate = dateObj.toISOString();
          }
        }

        const { data: newTask, error: insertError } = await supabase
          .from('primary_tasks')
          .insert({
            user_id: userId,
            title: title,
            due_date: isoDate
          })
          .select()
          .single();
        
        if (insertError) throw insertError;
        primaryTaskId = newTask.id;
      }

      // Step 2: Batch Insert Sub-tasks
      if (group.subTasks.length > 0) {
        const subTasksToInsert = group.subTasks.map(st => ({
          primary_task_id: primaryTaskId,
          title: st.title,
          estimated_minutes: st.estimated_minutes,
          priority: st.priority,
          priority_score: PRIORITY_SCORES[st.priority] || PRIORITY_SCORES.low,
          priority_band: st.priority,
          priority_reason: 'Imported from CSV priority column.',
          manual_priority_override: false
        }));

        // 4. DIAGNOSTIC LOG: Verify exact payload CONTENT before database hit
        // This will expose exactly what 'priority' string is being sent to Supabase
        console.log(`[${title}] Sending to Supabase:`, JSON.stringify(subTasksToInsert, null, 2));

        // ALWAYS use .insert() to prevent accidental overwrites via upsert/on_conflict
        const { data: stData, error: stError } = await supabase
          .from('sub_tasks')
          .insert(subTasksToInsert)
          .select();
        
        if (stError) throw stError;
        
        console.log(`[${title}] Successfully inserted ${stData.length} tasks.`);
        results.push({ course: title, subTasksCount: stData.length });
      }
    }

    console.log('--- DIAGNOSTIC COMPLETE ---');

    res.status(200).json({ 
      message: "CSV imported successfully", 
      details: results 
    });

  } catch (error) {
    console.error("Import Error Context:", error);
    res.status(500).json({ 
      error: "Failed to import CSV", 
      details: error.message 
    });
  }
};
