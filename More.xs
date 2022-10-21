#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"
#include <sys/types.h>
#include <sys/socket.h>
#include <ifaddrs.h>
#include <sys/un.h>

//Copy a sockaddr into an sv. BSD type systems have length field in struct
//sockaddr linux does not. So we cast the pointer to the correct family and
//then access the length field
//Returns a SV with the full sockaddr_* data
SV* sv_from_sockaddr(pTHX_ struct sockaddr *sockaddr){


	switch(sockaddr->sa_family){
		case AF_INET:
			return newSVpv((char *)sockaddr, sizeof(struct sockaddr_in));
			break;
		case AF_INET6:
			return newSVpv((char *)sockaddr, sizeof(struct sockaddr_in6));
			break;
		case AF_UNIX:
			return newSVpv((char *)sockaddr, sizeof(struct sockaddr_un));
			break;
		default:
			//TODO: use sockaddr_storage on linux?
			return newSVpv((char *)sockaddr, sizeof(struct sockaddr));
			break;
	}
	return NULL;
}


MODULE = Socket::More		PACKAGE = Socket::More		

INCLUDE: const-xs.inc
void
getifaddrs()


	INIT:
		struct ifaddrs *a;	
		struct ifaddrs *next;
		int ret;
		HV* h;
		UV count=0;

	PPCODE:
		ret=getifaddrs(&a);

		if(ret<0){
			switch(GIMME_V){
				case G_SCALAR:
				case G_VOID:
					XSRETURN_UNDEF;
					break;
				case G_ARRAY:
					XSRETURN_EMPTY;
					break;
				default:
					break;
			}
		}
		else{
			next=a->ifa_next;
			switch(GIMME_V){
				case G_SCALAR:
					while(next){
						count++;
						next=next->ifa_next;
					}
					//Free contents
					freeifaddrs(a);	
					mXPUSHs(newSVuv(count));
					XSRETURN(1);
					break;

				case G_VOID:
					XSRETURN_UNDEF;
					break;

				case G_ARRAY:

					//Copy contents
					while(next){
						//Create  hash 
						h=newHV();
						//Copy Values
						if(next->ifa_name){
							hv_stores(h, "name", newSVpv(next->ifa_name,0));
						}
						if(next->ifa_flags){
							hv_stores(h, "flags",newSVuv(next->ifa_flags));
						}
						if(next->ifa_addr){
							hv_stores(h, "addr", sv_from_sockaddr(aTHX_ next->ifa_addr));
						}
						if(next->ifa_netmask){
							hv_stores(h, "netmask", sv_from_sockaddr(aTHX_ next->ifa_netmask));
						}
						if(next->ifa_dstaddr){
							hv_stores(h, "dstaddr", sv_from_sockaddr(aTHX_ next->ifa_dstaddr));
						}

						//a->ifa_data... read into this more
						next=next->ifa_next;
						mXPUSHs(newRV((SV *)h));
						count++;
					}
					//Free contents
					freeifaddrs(a);	
					XSRETURN(count);
					break;
				default:
					break;
			}
		}
		


