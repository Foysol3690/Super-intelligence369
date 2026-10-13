// MAYA NEXØRA - Shizuku bridge used by MainActivity for lock/unlock commands.
package com.foysol.jarvis;

interface IMayaShizukuService {
    String execute(String requestJson) = 1;
}