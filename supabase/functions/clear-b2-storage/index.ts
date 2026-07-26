import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const b2ApiUrl = Deno.env.get("B2_API_URL");
const b2AuthToken = Deno.env.get("B2_AUTH_TOKEN");
const b2BucketId = Deno.env.get("B2_BUCKET_ID");

Deno.serve(async (req) => {
  // Only allow authenticated POST requests
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    // Verify auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response("Unauthorized", { status: 401 });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    let deletedCount = 0;
    let startFilename = "";
    const maxRetries = 5;

    console.log("🗑️ Starting B2 storage clearance...");

    // List and delete all files
    while (true) {
      let retryCount = 0;

      while (retryCount < maxRetries) {
        try {
          const listResponse = await fetch(
            `${b2ApiUrl}/b2api/v2/b2_list_file_versions?bucketId=${b2BucketId}&startFileName=${encodeURIComponent(startFilename)}&maxFileCount=1000`,
            {
              headers: {
                Authorization: b2AuthToken,
              },
            }
          );

          if (!listResponse.ok) {
            throw new Error(
              `B2 list failed: ${listResponse.status} ${listResponse.statusText}`
            );
          }

          const listData = await listResponse.json();
          const files = listData.files || [];

          if (files.length === 0) {
            console.log(`✅ No more files to delete`);
            break;
          }

          // Delete each file
          for (const file of files) {
            try {
              const deleteResponse = await fetch(
                `${b2ApiUrl}/b2api/v2/b2_delete_file_version?fileName=${encodeURIComponent(file.fileName)}&fileId=${file.fileId}`,
                {
                  method: "POST",
                  headers: {
                    Authorization: b2AuthToken,
                  },
                }
              );

              if (deleteResponse.ok) {
                deletedCount++;
                console.log(`🗑️ Deleted: ${file.fileName}`);
              } else {
                console.log(
                  `⚠️ Failed to delete ${file.fileName}: ${deleteResponse.status}`
                );
              }
            } catch (deleteError) {
              console.error(`Error deleting file ${file.fileName}:`, deleteError);
            }
          }

          // Check if there are more files
          if (!listData.nextFileName) {
            console.log(
              `✅ Clearance complete! Deleted ${deletedCount} files from B2`
            );
            break;
          }

          startFilename = listData.nextFileName;
          retryCount = 0; // Reset retry count on success
          break; // Exit retry loop
        } catch (error) {
          retryCount++;
          if (retryCount < maxRetries) {
            console.log(
              `⚠️ Retry ${retryCount}/${maxRetries} for listing files...`
            );
            await new Promise((resolve) => setTimeout(resolve, 1000));
          } else {
            throw error;
          }
        }
      }

      if (retryCount >= maxRetries) {
        break;
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `B2 storage cleared successfully`,
        filesDeleted: deletedCount,
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error clearing B2 storage:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
