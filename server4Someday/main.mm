//
//  main.m
//  server4Someday
//
//  Created by KudoCC on 14-7-9.
//  Copyright (c) 2014年 KudoCC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#import "KDPacket.h"
#import "KDNetworkUtility.h"

#define LISTENQ 5
#define SERV_PORT 70001

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        int listenfd = 0 ;
        int connfd = 0 ;
        socklen_t clilen ;
        struct sockaddr_in cliaddr, servaddr ;
        listenfd = socket (AF_INET, SOCK_STREAM, 0);
        bzero(&servaddr, sizeof(servaddr));
        servaddr.sin_family = AF_INET;
        servaddr.sin_addr.s_addr = htonl (INADDR_ANY);
        servaddr.sin_port = htons (SERV_PORT);
        bind(listenfd, (const struct sockaddr *)&servaddr, sizeof(servaddr));
        
        NSLog(@"begin listen on port:%d\n", SERV_PORT) ;
        int rLiten = listen(listenfd, LISTENQ);
        if (rLiten != 0) {
            printf("listen error:%d\n", errno) ;
            return -1 ;
        }
        for (; ; ) {
            clilen = sizeof(cliaddr);
            connfd = accept(listenfd, (struct sockaddr *)&cliaddr, &clilen);
            if (connfd < 0) {
                printf("error\n") ;
                break ;
            } else {
                const char *ip = inet_ntoa(cliaddr.sin_addr) ;
                int port = cliaddr.sin_port ;
                printf("accept from ip:%s, port:%d\n", ip, port) ;
            }
            
            while (1) {
                int fdInput = STDIN_FILENO ;
                
                fd_set readSet ;
                FD_SET(fdInput, &readSet) ;
                FD_SET(connfd, &readSet) ;
                
                int fdMax = fdInput > connfd ? fdInput : connfd ;
                struct timeval timeout ;
                timeout.tv_sec = 3 ;
                timeout.tv_usec = 0 ;
                int iSelect = select(fdMax+1, &readSet, NULL, NULL, &timeout) ;
                if (iSelect > 0) {
                    char readBuf[1024] ;
                    memset(readBuf, 0, sizeof(readBuf)) ;
                    if (FD_ISSET(fdInput, &readSet)) {
                        // standard input
                        unsigned int readLen = (unsigned int)read(fdInput, readBuf, sizeof(readBuf)-1) ;
                        if (readLen > 0) {
                            printf("read from standard input len %zd\n", readLen) ;
                            TextPacket s_packet ;
                            s_packet.header.transId = [KDNetworkUtility generatorTransId] ;
                            s_packet.textLen = readLen ;
                            s_packet.header.length = s_packet.packetLength() ;
                            memcpy(s_packet.text, readBuf, readLen) ;
                            KDPacket *packet = [KDPacket serialization:&s_packet] ;
                            NSData *data = [packet data] ;
                            ssize_t writeLen = write(connfd, data.bytes, [data length]) ;
                            if (writeLen > 0) {
                                printf("success write %zu\n", writeLen) ;
                            } else {
                                printf("write %zu, error %d\n", writeLen, errno) ;
                                break ;
                            }
                        } else if (readLen == 0) {
                            break ;
                        } else {
                            printf("read error %d\n", errno) ;
                        }
                    }
                    if (FD_ISSET(connfd, &readSet)) {
                        // socket
                        ssize_t readLen = read(connfd, readBuf, sizeof(readBuf)-1) ;
                        if (readLen > 0) {
                            printf("read from socket len %zd\n", readLen) ;
                            ssize_t writeLen = write(connfd, readBuf, readLen) ;
                            if (writeLen > 0) {
                                printf("success write %zu\n", writeLen) ;
                            } else {
                                printf("write %zu, error %d\n", writeLen, errno) ;
                                break ;
                            }
                        } else if (readLen == 0) {
                            break ;
                        } else {
                            printf("read error %d\n", errno) ;
                        }
                    }
                } else if (iSelect == 0) {
                    continue ;
                } else {
                    if (errno == EINTR) {
                        continue ;
                    } else {
                        printf("select error %d\n", errno) ;
                        break ;
                    }
                }
            }
            printf("connection closed\n") ;
            close(connfd) ;
        }
        close(listenfd);
    }
    
    return 0;
}

