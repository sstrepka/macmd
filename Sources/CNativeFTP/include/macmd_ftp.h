#ifndef MACMD_FTP_H
#define MACMD_FTP_H
#include <stddef.h>
#include <stdint.h>
typedef struct macmd_ftp_session macmd_ftp_session;
typedef int (*macmd_ftp_progress)(void *context, int64_t download_total, int64_t download_now, int64_t upload_total, int64_t upload_now);
typedef struct {
    const char *url;
    const char *username;
    const char *password;
    const char *account;
    const char *pinned_key;
    const char *ca_file;
    const char *client_certificate;
    const char *local_path;
    const char *commands;
    int protocol;
    int active;
    int operation; /* 0 listing, 1 download, 2 upload + postquote, 3 commands */
} macmd_ftp_request;
macmd_ftp_session *macmd_ftp_create(void);
void macmd_ftp_destroy(macmd_ftp_session *session);
const char *macmd_ftp_version(void);
int macmd_ftp_perform(macmd_ftp_session *session, const macmd_ftp_request *request,
                      macmd_ftp_progress progress, void *context,
                      unsigned char **output, size_t *output_size, char **error);
void macmd_ftp_free(void *memory);
#endif
