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
#import "PacketMemoryManager.h"

#define LISTENQ 5
#define SERV_PORT 7001

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
        
        printf("begin listen on port:%d\n", SERV_PORT) ;
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
            
            // set clientSocket to O_NONBLOCK
            int val = fcntl(connfd, F_GETFL, 0) ;
            fcntl(connfd, F_SETFL, val | O_NONBLOCK) ;
            
            /*
            // set socket send and receive buffer lenght
            int recvBufferLen = 2*1024 ;
            setsockopt(connfd ,SOL_SOCKET, SO_RCVBUF, (const char*)&recvBufferLen, sizeof(int)) ;
            int sendBufferLen = 2*1024 ;
            setsockopt(connfd, SOL_SOCKET,SO_SNDBUF, (const char*)&sendBufferLen, sizeof(int)) ;
             */
            
            CPacketMemoryManager socketReadBuffer = CPacketMemoryManager();
            CPacketMemoryManager standardInputBuffer = CPacketMemoryManager();
            CPacketMemoryManager writeBuffer = CPacketMemoryManager();

            // standard input no block
            int fdInput = STDIN_FILENO ;
            val = fcntl(fdInput, F_GETFL, 0) ;
            fcntl(fdInput, F_SETFL, val | O_NONBLOCK) ;
            
            fd_set readSet ;
            FD_ZERO(&readSet);
            fd_set writeSet;
            FD_ZERO(&writeSet);
            
            while (1) {
                int fdMax = fdInput > connfd ? fdInput : connfd ;
                struct timeval timeout ;
                timeout.tv_sec = 3 ;
                timeout.tv_usec = 0 ;
                
                FD_SET(fdInput, &readSet) ;
                FD_SET(connfd, &readSet) ;
                fd_set *pWriteFd = NULL ;
                if (writeBuffer.getUseBufferLength() > 0) {
                    FD_SET(connfd, &writeSet) ;
                    pWriteFd = &writeSet;
                } else {
                    FD_CLR(connfd, &writeSet) ;
                }
                int iSelect = select(fdMax+1, &readSet, pWriteFd, NULL, &timeout) ;
                if (iSelect > 0) {
                    if (pWriteFd && FD_ISSET(connfd, pWriteFd)) {
                        printf("now available send buffer to write\n") ;
                        // echo the message
                        unsigned int writeBufferLen = 0 ;
                        ssize_t writeLen = 0;
                        while ((writeBufferLen = writeBuffer.getUseBufferLength()) > 0) {
                            writeLen = send(connfd, writeBuffer.getBufferPointer(), writeBufferLen, 0) ;
                            if (writeLen > 0) {
                                writeBuffer.removeBuffer((unsigned int)writeLen) ;
                                printf("success send %zu\n", writeLen) ;
                            } else if (writeLen == 0) {
                                printf("send len is zero\n") ;
                            } else {
                                if (errno == EINTR) {
                                    printf("send function interrupted by a signal\n");
                                    continue;
                                }
                                printf("send %zu, error %d\n", writeLen, errno) ;
                                break ;
                            }
                        }
                        printf("write buffer size:%u\n", writeBuffer.getUseBufferLength()) ;
                    }
                    
                    if (FD_ISSET(fdInput, &readSet)) {
                        printf("standard input fd read\n");
                        unsigned char readBuf[1024] ;
                        memset(readBuf, 0, sizeof(readBuf)) ;
                        do {
                            ssize_t readLen = read(fdInput, readBuf, sizeof(readBuf)-1) ;
                            if (readLen > 0) {
                                printf("read from standard input len %zd\n", readLen) ;
                                standardInputBuffer.addToBuffer(readBuf, (unsigned int)readLen);
                            } else if (readLen == 0) {
                                printf("standard read lenght zero\n");
                                break;
                            } else {
                                if (errno != EAGAIN) {
                                    printf("read error %d\n", errno) ;
                                }
                                break;
                            }
                        } while (1);
                        
                        if (standardInputBuffer.getUseBufferLength() > 0) {
                            TextPacket s_packet;
                            s_packet.header.transId = [KDNetworkUtility generatorTransId];
                            s_packet.textLen = standardInputBuffer.getUseBufferLength();
                            s_packet.header.length = s_packet.packetLength();
                            memcpy(s_packet.text, readBuf, s_packet.textLen);
                            KDPacket *packet = [KDPacket serialization:&s_packet] ;
                            NSData *data = [packet data] ;
                            writeBuffer.addToBuffer((const unsigned char *)data.bytes, (unsigned int)data.length);
                            standardInputBuffer.removeBuffer(standardInputBuffer.getUseBufferLength());
                        }
                    }
                    
                    if (FD_ISSET(connfd, &readSet)) {
                        printf("socket input fd read\n");
                        // socket input
                        unsigned char bufferRead[2048] ;
                        long r = 0 ;
                        do {
                            r = read(connfd, bufferRead, sizeof(bufferRead)) ;
                            if (r > 0) {
                                printf("read len %ld\n", r) ;
                                socketReadBuffer.addToBuffer(bufferRead, (unsigned int)r) ;
                            }
                        } while (r > 0) ;
                        while (1) {
                            unsigned int len = socketReadBuffer.getUseBufferLength() ;
                            if (len > sizeof(NetWorkHeader)) {
                                unsigned char *p = socketReadBuffer.getBufferPointer() ;
                                NSData *data = [NSData dataWithBytes:p length:sizeof(BaseNetworkPacket)] ;
                                KDPacket *packet = [KDPacket deSerialization:data] ;
                                unsigned int packetLen = packet.packet->header.length ;
                                if (len < packetLen) {
                                    break ;
                                }
                                data = [NSData dataWithBytes:p length:packetLen] ;
                                packet = [KDPacket deSerialization:data] ;
                                writeBuffer.addToBuffer(p, packetLen);
                                socketReadBuffer.removeBuffer(packetLen) ;
                                
                                BaseNetworkPacket *basePacket = [packet packet] ;
                                if (basePacket->header.cmd == Cmd_Text) {
                                    TextPacket *textpacket = (TextPacket *)basePacket ;
                                    textpacket->text[textpacket->textLen] = '\0' ;
                                    printf("receive text message:%s\n", textpacket->text) ;
                                }
                            } else {
                                break ;
                            }
                        }
                        if (r < 0) {
                            if (errno == EAGAIN) {
                                // read would block but socket is set to nonblock
                            } else {
                                printf("read error %d\n", errno) ;
                                break ;
                            }
                        } else if (r == 0) {
                            printf("connection closed by peer\n") ;
                            break ;
                        }
                    }
                } else if (iSelect == 0) {
                    // timeout
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
