#include "macmd_ftp.h"
#include <curl/curl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>

struct macmd_ftp_session { CURL *easy; };
static pthread_once_t initialized = PTHREAD_ONCE_INIT;
static void initialize(void) { curl_global_init(CURL_GLOBAL_DEFAULT); }
macmd_ftp_session *macmd_ftp_create(void) {
    pthread_once(&initialized, initialize);
    macmd_ftp_session *session = calloc(1, sizeof(*session));
    if (session && !(session->easy = curl_easy_init())) { free(session); return NULL; }
    return session;
}
void macmd_ftp_destroy(macmd_ftp_session *session) {
    if (session) { curl_easy_cleanup(session->easy); free(session); }
}
const char *macmd_ftp_version(void) { return curl_version(); }
void macmd_ftp_free(void *memory) { free(memory); }
struct buffer { unsigned char *bytes; size_t count; };
static size_t collect(char *data, size_t size, size_t count, void *context) {
    struct buffer *buffer = context;
    if (size && count > SIZE_MAX / size) return 0;
    size_t length = size * count;
    if (length > 64 * 1024 * 1024 || buffer->count > 64 * 1024 * 1024 - length) return 0;
    unsigned char *next = realloc(buffer->bytes, buffer->count + length + 1);
    if (!next) return 0;
    buffer->bytes = next;
    memcpy(next + buffer->count, data, length);
    buffer->count += length;
    next[buffer->count] = 0;
    return length;
}
struct progress_context { macmd_ftp_progress callback; void *context; };
static int update(void *context, curl_off_t total_down, curl_off_t now_down, curl_off_t total_up, curl_off_t now_up) {
    struct progress_context *progress = context;
    return progress->callback ? progress->callback(progress->context, total_down, now_down, total_up, now_up) : 0;
}
static struct curl_slist *commands(const char *text) {
    struct curl_slist *list = NULL;
    char *copy = strdup(text ? text : "");
    char *save = NULL;
    for (char *command = strtok_r(copy, "\n", &save); command; command = strtok_r(NULL, "\n", &save)) {
        struct curl_slist *next = curl_slist_append(list, command);
        if (!next) { curl_slist_free_all(list); free(copy); return NULL; }
        list = next;
    }
    free(copy);
    return list;
}
int macmd_ftp_perform(macmd_ftp_session *session, const macmd_ftp_request *request,
                      macmd_ftp_progress progress, void *context,
                      unsigned char **output, size_t *output_size, char **error) {
    *output = NULL; *output_size = 0; *error = NULL;
    if (!session || !request) return CURLE_FAILED_INIT;
    CURL *easy = session->easy;
    // Reset request settings while retaining the connection, DNS and TLS session caches.
    curl_easy_reset(easy);
    struct buffer buffer = {0};
    struct progress_context tracking = {progress, context};
    struct curl_slist *quotes = commands(request->commands);
    FILE *file = NULL;
    CURLcode result = CURLE_OK;
    char detail[CURL_ERROR_SIZE] = {0};
#define SET(option, value) do { result = curl_easy_setopt(easy, option, value); if (result != CURLE_OK) goto done; } while (0)
    SET(CURLOPT_ERRORBUFFER, detail);
    SET(CURLOPT_URL, request->url);
    SET(CURLOPT_PROTOCOLS_STR, "ftp,ftps");
    SET(CURLOPT_USERNAME, request->username);
    SET(CURLOPT_PASSWORD, request->password);
    SET(CURLOPT_NOSIGNAL, 1L);
    SET(CURLOPT_CONNECTTIMEOUT, 15L);
    SET(CURLOPT_SERVER_RESPONSE_TIMEOUT, 20L);
    SET(CURLOPT_LOW_SPEED_TIME, 30L);
    SET(CURLOPT_LOW_SPEED_LIMIT, 1L);
    SET(CURLOPT_TCP_KEEPALIVE, 1L);
    SET(CURLOPT_FTP_SKIP_PASV_IP, 1L);
    SET(CURLOPT_FTP_USE_EPSV, 1L);
    SET(CURLOPT_XFERINFOFUNCTION, update);
    SET(CURLOPT_XFERINFODATA, &tracking);
    SET(CURLOPT_NOPROGRESS, 0L);
    SET(CURLOPT_WRITEFUNCTION, collect);
    SET(CURLOPT_WRITEDATA, &buffer);
    if (request->active) SET(CURLOPT_FTPPORT, "-");
    if (request->account && *request->account) SET(CURLOPT_FTP_ACCOUNT, request->account);
    if (request->ca_file && *request->ca_file) SET(CURLOPT_CAINFO, request->ca_file);
    if (request->client_certificate && *request->client_certificate) SET(CURLOPT_SSLCERT, request->client_certificate);
    if (request->protocol == 0 || request->protocol == 3 || request->protocol == 4) {
        SET(CURLOPT_USE_SSL, (long)(request->protocol == 0 && !*request->pinned_key ? CURLUSESSL_TRY : CURLUSESSL_ALL));
        SET(CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
    }
    if (request->pinned_key && *request->pinned_key) {
        SET(CURLOPT_SSL_VERIFYPEER, 0L);
        SET(CURLOPT_SSL_VERIFYHOST, 0L);
        SET(CURLOPT_PINNEDPUBLICKEY, request->pinned_key);
        SET(CURLOPT_USE_SSL, (long)CURLUSESSL_ALL);
    }
    if (request->operation == 1) {
        file = fopen(request->local_path, "wb");
        if (!file) { result = CURLE_WRITE_ERROR; snprintf(detail, sizeof(detail), "Could not open local staging file."); goto done; }
        SET(CURLOPT_WRITEFUNCTION, NULL);
        SET(CURLOPT_WRITEDATA, file);
    } else if (request->operation == 2) {
        struct stat info;
        file = fopen(request->local_path, "rb");
        if (!file || fstat(fileno(file), &info)) { result = CURLE_READ_ERROR; snprintf(detail, sizeof(detail), "Could not open local upload file."); goto done; }
        SET(CURLOPT_UPLOAD, 1L);
        SET(CURLOPT_READDATA, file);
        SET(CURLOPT_INFILESIZE_LARGE, (curl_off_t)info.st_size);
        SET(CURLOPT_FTP_CREATE_MISSING_DIRS, (long)CURLFTP_CREATE_DIR_RETRY);
        SET(CURLOPT_POSTQUOTE, quotes);
        SET(CURLOPT_UPLOAD_BUFFERSIZE, 256L * 1024L);
    } else if (request->operation == 3) {
        SET(CURLOPT_QUOTE, quotes);
        SET(CURLOPT_NOBODY, 1L);
    }
    result = curl_easy_perform(easy);
done:
    if (file && fclose(file) && result == CURLE_OK) result = CURLE_WRITE_ERROR;
    // Do not leave callbacks, command lists, FILE pointers or credentials pointing
    // into a completed Swift request. Reset does not close reusable connections.
    curl_easy_reset(easy);
    curl_slist_free_all(quotes);
    if (result != CURLE_OK) *error = strdup(*detail ? detail : curl_easy_strerror(result));
    *output = buffer.bytes; *output_size = buffer.count;
    return result;
#undef SET
}
