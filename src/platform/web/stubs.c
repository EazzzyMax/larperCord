/* Navegador (src/web_main.zig): o que a página não tem. A demonstração não usa rede
 * (curl), voz (Opus, DAVE), WebP nem o fontconfig, mas o código que chama essas
 * bibliotecas está no mesmo executável. Aqui cada uma responde "não dá", do jeito
 * que o app já trata quando uma delas falha. Os cabeçalhos de verdade conferem que
 * as assinaturas batem (no wasm, assinatura errada vira armadilha na hora da chamada).
 * Também usado pelo web-sim, que não liga essas bibliotecas. */
#define CURL_DISABLE_TYPECHECK 1
#include <stdlib.h>
#include <curl/curl.h>
#include <opus/opus.h>
#include <webp/decode.h>
#include <webp/demux.h>
#include <fontconfig/fontconfig.h>
#include <dave/dave.h>

#undef curl_easy_setopt
#undef curl_easy_getinfo

/* --- curl: sem rede ----------------------------------------------------------- */

CURLcode curl_global_init(long flags) { (void)flags; return CURLE_FAILED_INIT; }
CURL *curl_easy_init(void) { return NULL; }
void curl_easy_cleanup(CURL *curl) { (void)curl; }
void curl_easy_reset(CURL *curl) { (void)curl; }
CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...) { (void)curl; (void)option; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...) { (void)curl; (void)info; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_easy_perform(CURL *curl) { (void)curl; return CURLE_UNSUPPORTED_PROTOCOL; }
const char *curl_easy_strerror(CURLcode error) { (void)error; return "no network in the browser demo"; }
struct curl_slist *curl_slist_append(struct curl_slist *list, const char *data) { (void)data; return list; }
void curl_slist_free_all(struct curl_slist *list) { (void)list; }
curl_mime *curl_mime_init(CURL *easy) { (void)easy; return NULL; }
void curl_mime_free(curl_mime *mime) { (void)mime; }
curl_mimepart *curl_mime_addpart(curl_mime *mime) { (void)mime; return NULL; }
CURLcode curl_mime_name(curl_mimepart *part, const char *name) { (void)part; (void)name; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_mime_type(curl_mimepart *part, const char *mimetype) { (void)part; (void)mimetype; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_mime_data(curl_mimepart *part, const char *data, size_t datasize) { (void)part; (void)data; (void)datasize; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_mime_filedata(curl_mimepart *part, const char *filename) { (void)part; (void)filename; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_mime_filename(curl_mimepart *part, const char *filename) { (void)part; (void)filename; return CURLE_UNSUPPORTED_PROTOCOL; }
CURLcode curl_ws_recv(CURL *curl, void *buffer, size_t buflen, size_t *recv, const struct curl_ws_frame **metap) {
    (void)curl; (void)buffer; (void)buflen; (void)metap;
    if (recv) *recv = 0;
    return CURLE_UNSUPPORTED_PROTOCOL;
}
CURLcode curl_ws_send(CURL *curl, const void *buffer_arg, size_t buflen, size_t *sent, curl_off_t fragsize, unsigned int flags) {
    (void)curl; (void)buffer_arg; (void)buflen; (void)fragsize; (void)flags;
    if (sent) *sent = 0;
    return CURLE_UNSUPPORTED_PROTOCOL;
}

/* --- Opus: sem voz nem mensagem de voz --------------------------------------- */

OpusDecoder *opus_decoder_create(opus_int32 Fs, int channels, int *error) { (void)Fs; (void)channels; if (error) *error = OPUS_UNIMPLEMENTED; return NULL; }
void opus_decoder_destroy(OpusDecoder *st) { (void)st; }
int opus_decoder_ctl(OpusDecoder *st, int request, ...) { (void)st; (void)request; return OPUS_UNIMPLEMENTED; }
int opus_decode(OpusDecoder *st, const unsigned char *data, opus_int32 len, opus_int16 *pcm, int frame_size, int decode_fec) {
    (void)st; (void)data; (void)len; (void)pcm; (void)frame_size; (void)decode_fec;
    return OPUS_UNIMPLEMENTED;
}
OpusEncoder *opus_encoder_create(opus_int32 Fs, int channels, int application, int *error) { (void)Fs; (void)channels; (void)application; if (error) *error = OPUS_UNIMPLEMENTED; return NULL; }
void opus_encoder_destroy(OpusEncoder *st) { (void)st; }
int opus_encoder_ctl(OpusEncoder *st, int request, ...) { (void)st; (void)request; return OPUS_UNIMPLEMENTED; }
opus_int32 opus_encode(OpusEncoder *st, const opus_int16 *pcm, int frame_size, unsigned char *data, opus_int32 max_data_bytes) {
    (void)st; (void)pcm; (void)frame_size; (void)data; (void)max_data_bytes;
    return OPUS_UNIMPLEMENTED;
}

/* --- WebP: a demonstração gera as imagens em PNG/GIF -------------------------- */

uint8_t *WebPDecodeRGBA(const uint8_t *data, size_t data_size, int *width, int *height) { (void)data; (void)data_size; (void)width; (void)height; return NULL; }
void WebPFree(void *ptr) { free(ptr); }
VP8StatusCode WebPGetFeaturesInternal(const uint8_t *data, size_t data_size, WebPBitstreamFeatures *features, int version) {
    (void)data; (void)data_size; (void)features; (void)version;
    return VP8_STATUS_UNSUPPORTED_FEATURE;
}
int WebPAnimDecoderOptionsInitInternal(WebPAnimDecoderOptions *opts, int version) { (void)opts; (void)version; return 0; }
WebPAnimDecoder *WebPAnimDecoderNewInternal(const WebPData *data, const WebPAnimDecoderOptions *opts, int version) { (void)data; (void)opts; (void)version; return NULL; }
int WebPAnimDecoderGetInfo(const WebPAnimDecoder *dec, WebPAnimInfo *info) { (void)dec; (void)info; return 0; }
int WebPAnimDecoderGetNext(WebPAnimDecoder *dec, uint8_t **buf, int *timestamp) { (void)dec; (void)buf; (void)timestamp; return 0; }
int WebPAnimDecoderHasMoreFrames(const WebPAnimDecoder *dec) { (void)dec; return 0; }
void WebPAnimDecoderReset(WebPAnimDecoder *dec) { (void)dec; }
void WebPAnimDecoderDelete(WebPAnimDecoder *dec) { (void)dec; }

/* --- fontconfig: as fontes vêm da página (ui/fonts.zig, resolveWeb) ----------- */

void FcFini(void) {}

/* --- DAVE: sem voz ------------------------------------------------------------ */

uint16_t daveMaxSupportedProtocolVersion(void) { return 0; }
void daveSetLogSinkCallback(DAVELogSinkCallback callback) { (void)callback; }
void daveFree(void *ptr) { free(ptr); }
DAVESessionHandle daveSessionCreate(void *context, const char *authSessionId, DAVEMLSFailureCallback callback, void *userData) {
    (void)context; (void)authSessionId; (void)callback; (void)userData;
    return NULL;
}
void daveSessionDestroy(DAVESessionHandle session) { (void)session; }
void daveSessionInit(DAVESessionHandle session, uint16_t version, uint64_t groupId, const char *selfUserId) { (void)session; (void)version; (void)groupId; (void)selfUserId; }
void daveSessionReset(DAVESessionHandle session) { (void)session; }
void daveSessionSetExternalSender(DAVESessionHandle session, const uint8_t *externalSender, size_t length) { (void)session; (void)externalSender; (void)length; }
void daveSessionGetMarshalledKeyPackage(DAVESessionHandle session, uint8_t **keyPackage, size_t *length) {
    (void)session;
    if (keyPackage) *keyPackage = NULL;
    if (length) *length = 0;
}
void daveSessionProcessProposals(DAVESessionHandle session, const uint8_t *proposals, size_t length, const char **recognizedUserIds, size_t recognizedUserIdsLength, uint8_t **commitWelcomeBytes, size_t *commitWelcomeBytesLength) {
    (void)session; (void)proposals; (void)length; (void)recognizedUserIds; (void)recognizedUserIdsLength;
    if (commitWelcomeBytes) *commitWelcomeBytes = NULL;
    if (commitWelcomeBytesLength) *commitWelcomeBytesLength = 0;
}
DAVECommitResultHandle daveSessionProcessCommit(DAVESessionHandle session, const uint8_t *commit, size_t length) { (void)session; (void)commit; (void)length; return NULL; }
DAVEWelcomeResultHandle daveSessionProcessWelcome(DAVESessionHandle session, const uint8_t *welcome, size_t length, const char **recognizedUserIds, size_t recognizedUserIdsLength) {
    (void)session; (void)welcome; (void)length; (void)recognizedUserIds; (void)recognizedUserIdsLength;
    return NULL;
}
DAVEKeyRatchetHandle daveSessionGetKeyRatchet(DAVESessionHandle session, const char *userId) { (void)session; (void)userId; return NULL; }
bool daveCommitResultIsFailed(DAVECommitResultHandle commitResultHandle) { (void)commitResultHandle; return true; }
bool daveCommitResultIsIgnored(DAVECommitResultHandle commitResultHandle) { (void)commitResultHandle; return false; }
void daveCommitResultDestroy(DAVECommitResultHandle commitResultHandle) { (void)commitResultHandle; }
void daveWelcomeResultDestroy(DAVEWelcomeResultHandle welcomeResultHandle) { (void)welcomeResultHandle; }
void daveKeyRatchetDestroy(DAVEKeyRatchetHandle keyRatchet) { (void)keyRatchet; }
DAVEEncryptorHandle daveEncryptorCreate(void) { return NULL; }
void daveEncryptorDestroy(DAVEEncryptorHandle encryptor) { (void)encryptor; }
void daveEncryptorSetKeyRatchet(DAVEEncryptorHandle encryptor, DAVEKeyRatchetHandle keyRatchet) { (void)encryptor; (void)keyRatchet; }
bool daveEncryptorHasKeyRatchet(DAVEEncryptorHandle encryptor) { (void)encryptor; return false; }
void daveEncryptorAssignSsrcToCodec(DAVEEncryptorHandle encryptor, uint32_t ssrc, DAVECodec codecType) { (void)encryptor; (void)ssrc; (void)codecType; }
size_t daveEncryptorGetMaxCiphertextByteSize(DAVEEncryptorHandle encryptor, DAVEMediaType mediaType, size_t frameSize) { (void)encryptor; (void)mediaType; (void)frameSize; return 0; }
DAVEEncryptorResultCode daveEncryptorEncrypt(DAVEEncryptorHandle encryptor, DAVEMediaType mediaType, uint32_t ssrc, const uint8_t *frame, size_t frameLength, uint8_t *encryptedFrame, size_t encryptedFrameCapacity, size_t *bytesWritten) {
    (void)encryptor; (void)mediaType; (void)ssrc; (void)frame; (void)frameLength; (void)encryptedFrame; (void)encryptedFrameCapacity;
    if (bytesWritten) *bytesWritten = 0;
    return DAVE_ENCRYPTOR_RESULT_CODE_MISSING_CRYPTOR;
}
DAVEDecryptorHandle daveDecryptorCreate(void) { return NULL; }
void daveDecryptorDestroy(DAVEDecryptorHandle decryptor) { (void)decryptor; }
void daveDecryptorTransitionToKeyRatchet(DAVEDecryptorHandle decryptor, DAVEKeyRatchetHandle keyRatchet) { (void)decryptor; (void)keyRatchet; }
void daveDecryptorTransitionToPassthroughMode(DAVEDecryptorHandle decryptor, bool passthroughMode) { (void)decryptor; (void)passthroughMode; }
size_t daveDecryptorGetMaxPlaintextByteSize(DAVEDecryptorHandle decryptor, DAVEMediaType mediaType, size_t encryptedFrameSize) { (void)decryptor; (void)mediaType; (void)encryptedFrameSize; return 0; }
DAVEDecryptorResultCode daveDecryptorDecrypt(DAVEDecryptorHandle decryptor, DAVEMediaType mediaType, const uint8_t *encryptedFrame, size_t encryptedFrameLength, uint8_t *frame, size_t frameCapacity, size_t *bytesWritten) {
    (void)decryptor; (void)mediaType; (void)encryptedFrame; (void)encryptedFrameLength; (void)frame; (void)frameCapacity;
    if (bytesWritten) *bytesWritten = 0;
    return DAVE_DECRYPTOR_RESULT_CODE_DECRYPTION_FAILURE;
}

/* --- SDL3 no Emscripten: a porta não compila os subsistemas de processo e de
 * diálogo de arquivo. Responde como os backends "dummy" do próprio SDL: nenhum
 * processo abre e o diálogo devolve a lista nula com erro. Só no wasm: o web-sim
 * liga o SDL3 do sistema, que tem os dois. --------------------------------------- */

#ifdef __EMSCRIPTEN__
#include <SDL3/SDL.h>

SDL_Process *SDL_CreateProcess(const char * const *args, bool pipe_stdio) { (void)args; (void)pipe_stdio; SDL_Unsupported(); return NULL; }
SDL_Process *SDL_CreateProcessWithProperties(SDL_PropertiesID props) { (void)props; SDL_Unsupported(); return NULL; }
SDL_PropertiesID SDL_GetProcessProperties(SDL_Process *process) { (void)process; return 0; }
SDL_IOStream *SDL_GetProcessInput(SDL_Process *process) { (void)process; return NULL; }
SDL_IOStream *SDL_GetProcessOutput(SDL_Process *process) { (void)process; return NULL; }
bool SDL_KillProcess(SDL_Process *process, bool force) { (void)process; (void)force; return SDL_Unsupported(); }
bool SDL_WaitProcess(SDL_Process *process, bool block, int *exitcode) {
    (void)process; (void)block;
    if (exitcode) *exitcode = -1;
    /* Sem processo não há o que esperar: quem chama já pode soltar o ponteiro. */
    return true;
}
void SDL_DestroyProcess(SDL_Process *process) { (void)process; }

void SDL_ShowOpenFileDialog(SDL_DialogFileCallback callback, void *userdata, SDL_Window *window, const SDL_DialogFileFilter *filters, int nfilters, const char *default_location, bool allow_many) {
    (void)window; (void)filters; (void)nfilters; (void)default_location; (void)allow_many;
    SDL_Unsupported();
    if (callback) callback(userdata, NULL, -1);
}

/* --- Sockets: no Emscripten o connect() e o sendto() viram um WebSocket para o
 * endereço pedido. A demonstração não usa rede (o gateway é de mentira), mas o código
 * da voz, do Rich Presence e do TCP local está no executável: aqui nenhum socket abre,
 * e nada sai da aba nem por engano. Estes ficam no lugar dos da libc. */

#include <errno.h>
#include <sys/socket.h>

int socket(int domain, int type, int protocol) {
    (void)domain; (void)type; (void)protocol;
    errno = EAFNOSUPPORT;
    return -1;
}
int socketpair(int domain, int type, int protocol, int fd[2]) {
    (void)domain; (void)type; (void)protocol; (void)fd;
    errno = EAFNOSUPPORT;
    return -1;
}
#endif
