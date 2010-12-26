/*
  Modifies the FakeOperator plist as a scheduled task. Displays current prepaid balance instead of operator, retrieved via AT command.
*/

#include <stdio.h>
#include <string.h>
#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <errno.h>
#include <time.h>

#define BUFSIZE (65536+100)

/* 
 Start of 'sendmodem' code. 
 ------------------------------------------------------------------------------
*/

unsigned char readbuf[BUFSIZE];

static struct termios term;
static struct termios gOriginalTTYAttrs;
int InitConn(int speed);

void SendCmd(int modem, void *buf, size_t size)
{
    if(write(modem, buf, size) == -1) {
        fprintf(stderr, "SendCmd error. %s\n", strerror(errno));
        exit(1);
    }
}

void SendStrCmd(int modem, char *buf)
{
    fprintf(stderr,"Sending command to modem: %s\n",buf);
    SendCmd(modem, buf, strlen(buf));
}

NSString * ReadResp(int modem, int timeoutSec)
{
    int len = 0;
    struct timeval timeout;
    int nfds = modem + 1;
    fd_set readfds;
    int select_ret;
	
    FD_ZERO(&readfds);
    FD_SET(modem, &readfds);
	
    // Wait 10 seconds for carrier response
    timeout.tv_sec = timeoutSec;
    timeout.tv_usec = 500000;
	
    fprintf(stderr,"-");
    while ((select_ret = select(nfds, &readfds, NULL, NULL, &timeout)) > 0) {
        fprintf(stderr,".");
        len += read(modem, readbuf + len, BUFSIZE - len);
        FD_ZERO(&readfds);
        FD_SET(modem, &readfds);
        timeout.tv_sec = 0;
        timeout.tv_usec = 500000;
    }
    if (len > 0) {
        fprintf(stderr,"+\n");
    }
	
	readbuf[len] = 0;

	NSString *responseString = [NSString stringWithCString:(const char *)readbuf encoding:NSUTF8StringEncoding];
	
    return responseString;
}

int InitConn(int speed)
{
    int modem = open("/dev/tty.debug", O_RDWR | O_NOCTTY);
	
    if(modem == -1) {
        fprintf(stderr, "%i(%s)\n", errno, strerror(errno));
        exit(1);
    }
	
    ioctl(modem, TIOCEXCL);
    fcntl(modem, F_SETFL, 0);
	
    tcgetattr(modem, &term);
    gOriginalTTYAttrs = term;
	
    cfmakeraw(&term);
    cfsetspeed(&term, speed);
    term.c_cflag = CS8 | CLOCAL | CREAD;
    term.c_iflag = 0;
    term.c_oflag = 0;
    term.c_lflag = 0;
    term.c_cc[VMIN] = 0;
    term.c_cc[VTIME] = 0;
    tcsetattr(modem, TCSANOW, &term);
	
    return modem;
}
void CloseConn(int modem)
{
    tcdrain(modem);
    tcsetattr(modem, TCSANOW, &gOriginalTTYAttrs);
    close(modem);
}

void SendAT(int fd)
{
    char cmd[5];
	
    //  SendStrCmd(fd, "AT\r");
    sprintf(cmd,"AT\r");
    SendCmd(fd, cmd, strlen(cmd));
}

void AT(int fd)
{
    fprintf(stderr, "Sending command to modem: AT\n");
    SendAT(fd);
    for (;;) {
        if(ReadResp(fd, 1) != 0) {
            if(strstr((const char *)readbuf,"OK") != NULL)
            {
                break;
            }
        }
        SendAT(fd);
    }
}

/* 
 End of 'sendmodem' code. 
 ------------------------------------------------------------------------------
*/

void SetOperator(NSString *operatorString)
{
	// Writing 'FakeCarrier' value to preference plist.
	NSString *filePath = @"/var/mobile/Library/Preferences/com.nspwn.fakeoperatorpreferences.plist";
	NSMutableDictionary *plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:filePath];
	[plistDict setValue:operatorString forKey:@"FakeCarrier"];
	[plistDict writeToFile:filePath atomically: YES];
	[plistDict release];
	// Posting FakeOperator notification via Darwin Notify Center.
	CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();	
	CFNotificationCenterPostNotification(r, CFSTR("com.nspwn.fakeoperator/operatorChanged"), NULL, NULL, TRUE);
}

int main(int argc, char **argv){
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	int modem;
	char cmd[1024];	
	NSString *responseString;
	
	// Set AT command to fetch balance 
	sprintf(cmd,"AT+CUSD=1,\"##122#\",15\r");
	
	modem = InitConn(115200);
	
	NSLog (@"Waiting for modem to be free..");
	AT(modem); // wait for device to be free, by polling with AT commands.
	
	NSLog (@"Requesting Prepaid balance from PCCW..");
	SendStrCmd(modem,cmd);
	
	NSRange check;
	// Loop til we find the balance response
	for (int i=0;i<20;i++) {
        if((responseString = ReadResp(modem, 10))) {
			check = [responseString rangeOfString: @"$"];
            if(check.length > 0){
                break;
            }
        }
		NSLog (@"Skipping: %@", responseString);
    }
	
	CloseConn(modem);
	
	NSLog (@"Response: %@", responseString);
	
	// Parse prepaid balance (first string between '$' and ',')
	NSRange match;
	match = [responseString rangeOfString: @"$"]; // Find first occurence of $
	responseString = [responseString substringFromIndex: match.location];
	match = [responseString rangeOfString: @","]; // First occurence of , after $
	NSString *balance = [responseString substringToIndex: match.location];
	
	NSLog (@"Fetched balance. Setting operator to: %@", balance);
	SetOperator(balance);
	
	[pool release];
	return 0;
}
