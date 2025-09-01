#include <stdio.h>
#include <stdlib.h>
#include <unistd.h> // for sleep()

#include "cJSON.h"
#include "bngblaster_api.h"

// A simple BNGBlaster configuration for demonstration
const char *BNGBLASTER_CONFIG =
                "{"
                "    \"sessions\": {"
                "        \"count\": 2,"
                "        \"max-outstanding\": 1000,"
                "        \"username\": \"bngblaster\","
                "        \"password\": \"bngblaster\""
                "    },"
                "    \"interfaces\": {"
                "        \"access\": {"
                "            \"interface\": \"veth1\","
                "            \"vlan\": [{\"id\": 900, \"sub-id\": 901}]"
                "        }"
                "    }"
                "}";

// Helper function to check for errors and exit
void check_error (bngblaster_error_t err, bngblaster_ctx_t *ctx, const char *message)
{
    if (err != BBERR_OK) {
        fprintf (stderr, "Error: %s\n", message);
        fprintf (stderr, "  API Error Code: %d (%s)\n", err, bngblaster_strerror (err));
        fprintf (stderr, "  Detailed Error: %s\n", bngblaster_get_last_error (ctx));
        bngblaster_free (ctx);
        exit (EXIT_FAILURE);
    }
}

int main (int argc, char *argv[])
{
    const char *host = "127.0.0.1";
    int port = 8080;

    if (argc > 1) {
        host = argv[1];
    }
    if (argc > 2) {
        port = atoi (argv[2]);
    }

    printf ("Connecting to BNGBlaster controller at %s:%d\n", host, port);

    bngblaster_ctx_t *ctx = bngblaster_init (host, port);
    if (!ctx) {
        fprintf (stderr, "Failed to initialize BNGBlaster API context.\n");
        return EXIT_FAILURE;
    }

    char *response = NULL;
    bngblaster_error_t err;

    // 1. Start a BNGBlaster instance
    printf ("\n=== 1. Starting BNGBlaster instance ===\n");
    err = bngblaster_start (ctx, BNGBLASTER_CONFIG, &response);
    check_error (err, ctx, "Failed to start BNGBlaster instance");
    printf ("Start Response: %s\n", response);

    // Parse the response to get the instance_id using cJSON
    int instance_id = -1;
    cJSON *root_json = cJSON_Parse (response);
    free (response); // We can free the string buffer now
    response = NULL;
    if (!root_json) {
        fprintf (stderr, "Failed to parse start response JSON: %s\n", cJSON_GetErrorPtr());
        bngblaster_free (ctx);
        return EXIT_FAILURE;
    }

    cJSON *id_json = cJSON_GetObjectItemCaseSensitive (root_json, "instance_id");
    if (cJSON_IsNumber (id_json)) {
        instance_id = id_json->valueint;
        printf ("Instance started with ID: %d\n", instance_id);
    } else {
        fprintf (stderr, "Could not find 'instance_id' in start response\n");
        cJSON_Delete (root_json);
        bngblaster_free (ctx);
        return EXIT_FAILURE;
    }
    cJSON_Delete (root_json); // Clean up the parsed JSON object

    printf ("\nWaiting for sessions to establish...\n");
    sleep (5);

    // 2. Get global stats
    printf ("\n=== 2. Getting Global Stats ===\n");
    err = bngblaster_get_stats (ctx, &response);
    check_error (err, ctx, "Failed to get stats");
    printf ("Stats Response: %s\n", response);
    free (response);
    response = NULL;

    // 3. Get info for session #1
    printf ("\n=== 3. Getting Info for Session 1 ===\n");
    err = bngblaster_get_session_info (ctx, 1, &response);
    check_error (err, ctx, "Failed to get session info");
    printf ("Session 1 Info: %s\n", response);
    free (response);
    response = NULL;

    // 4. Terminate session #2
    printf ("\n=== 4. Terminating Session 2 ===\n");
    err = bngblaster_session_command (ctx, "terminate", 2, &response);
    check_error (err, ctx, "Failed to terminate session");
    printf ("Terminate Response: %s\n", response);
    free (response);
    response = NULL;

    sleep (2);

    // 5. Stop the BNGBlaster instance
    printf ("\n=== 5. Stopping BNGBlaster instance %d ===\n", instance_id);
    err = bngblaster_stop (ctx, instance_id, &response);
    check_error (err, ctx, "Failed to stop BNGBlaster instance");
    printf ("Stop Response: %s\n", response);
    free (response);
    response = NULL;

    // Clean up
    bngblaster_free (ctx);
    printf ("\nSuccessfully completed BNGBlaster management cycle.\n");

    return EXIT_SUCCESS;
}