import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// Initialize Supabase client
const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
const supabase = createClient(supabaseUrl, supabaseKey)

// Queue configuration
const BATCH_SIZE = 100
const BATCH_DELAY_MS = 500
const MAX_RETRIES = 3

// In-memory queue (will persist as long as function is running)
let queue: any[] = []
let isProcessing = false
let statsProcessed = 0
let statsFailed = 0

/**
 * Process queue in batches
 */
async function processQueue() {
  if (isProcessing || queue.length === 0) {
    return
  }

  isProcessing = true
  console.log(`🚀 [BATCH] Starting batch processing. Queue size: ${queue.length}`)

  while (queue.length > 0) {
    // Get next batch
    const batchSize = Math.min(BATCH_SIZE, queue.length)
    const batch = queue.splice(0, batchSize)

    console.log(`📦 [BATCH] Processing batch of ${batchSize} items`)

    // Process batch with retry logic
    const results = await Promise.allSettled(
      batch.map((item) => insertAttendanceRecord(item))
    )

    // Count successes/failures
    const successCount = results.filter((r) => r.status === "fulfilled").length
    const failureCount = batchSize - successCount

    statsProcessed += successCount
    statsFailed += failureCount

    console.log(
      `✅ [BATCH] Batch complete. Success: ${successCount}, Failed: ${failureCount}`
    )
    console.log(
      `   Total Progress: ${statsProcessed} processed, ${statsFailed} failed`
    )

    // Wait before next batch to avoid overwhelming database
    if (queue.length > 0) {
      console.log(`⏳ [BATCH] Waiting ${BATCH_DELAY_MS}ms before next batch...`)
      await new Promise((resolve) => setTimeout(resolve, BATCH_DELAY_MS))
    }
  }

  isProcessing = false
  console.log(`🎉 [BATCH] Queue processing complete!`)
  console.log(`   Total: ${statsProcessed} success, ${statsFailed} failed`)
}

/**
 * Insert attendance record with retry logic - RETURNS RESULT
 */
async function insertAttendanceRecord(
  record: any,
  retryCount = 0
): Promise<{
  success: boolean
  attendance_id?: string
  reason?: string
  face_confidence?: number
}> {
  try {
    console.log(`   📝 Inserting: ${record.sr_no} (${record.record_type})`)

    // Add generated ID and timestamp
    const attendanceId = crypto.randomUUID()
    const insertRecord = {
      ...record,
      id: attendanceId,
      created_at: new Date().toISOString(),
    }

    const { error, data } = await supabase
      .from("attendance")
      .insert([insertRecord])
      .select()

    if (error) throw error

    console.log(`   ✅ Success: ${record.sr_no} - ID: ${attendanceId}`)

    return {
      success: true,
      attendance_id: attendanceId,
      face_confidence: record.similarity_score || 0,
    }
  } catch (error) {
    console.error(`   ❌ Error: ${record.sr_no} - ${error}`)

    // Retry logic
    if (retryCount < MAX_RETRIES) {
      console.log(
        `   🔄 Retrying... (Attempt ${retryCount + 1}/${MAX_RETRIES})`
      )
      await new Promise((resolve) => setTimeout(resolve, 2000)) // Wait 2s before retry
      return insertAttendanceRecord(record, retryCount + 1)
    }

    return {
      success: false,
      reason: `Failed after ${MAX_RETRIES} retries: ${error}`,
    }
  }
}

/**
 * Main handler
 */
serve(async (req) => {
  // Handle CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    })
  }

  try {
    if (req.method === "POST") {
      const body = await req.json()

      // Single record
      if (!Array.isArray(body)) {
        console.log(`📋 [SINGLE] Received 1 record`)

        // Process immediately (don't queue single records)
        const result = await insertAttendanceRecord(body)

        if (result.success) {
          console.log(`✅ [SINGLE] Success: ${result.attendance_id}`)
          return new Response(
            JSON.stringify({
              success: true,
              attendance_id: result.attendance_id,
              marked_time: body.marked_time,
              face_confidence: result.face_confidence,
              message: "Attendance marked successfully",
            }),
            {
              status: 200,
              headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
              },
            }
          )
        } else {
          console.log(`❌ [SINGLE] Failed: ${result.reason}`)
          return new Response(
            JSON.stringify({
              success: false,
              reason: result.reason,
              error_id: crypto.randomUUID(),
            }),
            {
              status: 400,
              headers: {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
              },
            }
          )
        }
      }

      // Batch records - queue them for async processing
      const records = Array.isArray(body) ? body : [body]
      console.log(`📋 [BATCH] Received ${records.length} record(s)`)

      // Add to queue
      queue.push(...records)
      console.log(`📋 [BATCH] Queue size now: ${queue.length}`)

      // Start processing in background
      processQueue()

      // Return queue status
      return new Response(
        JSON.stringify({
          success: true,
          message: `${records.length} records queued for batch processing`,
          queueSize: queue.length,
          processed: statsProcessed,
          failed: statsFailed,
        }),
        {
          status: 202, // Accepted (async processing)
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      )
    }

    // GET endpoint - return queue status
    if (req.method === "GET") {
      return new Response(
        JSON.stringify({
          queueSize: queue.length,
          isProcessing,
          totalProcessed: statsProcessed,
          totalFailed: statsFailed,
          timestamp: new Date().toISOString(),
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      )
    }

    return new Response("Method not allowed", { status: 405 })
  } catch (error) {
    console.error("❌ [ERROR]", error)
    return new Response(
      JSON.stringify({
        success: false,
        error: String(error),
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    )
  }
})
