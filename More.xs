#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
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
		

SV *
if_nametoindex(name)
	SV *name;
	INIT:
		char *p;
		unsigned int ret;
		int len;
	PPCODE:

		if(SvOK(name)&&SvPOK(name)){
			len=SvCUR(name);
			p=SvGROW(name, len+1);	
			p[len]='\0';

			ret=if_nametoindex(p);	
			mXPUSHs(newSVuv(ret));
			XSRETURN(1);
		}
		else {
			XSRETURN_UNDEF;
		}


SV *
if_indextoname(index)

	SV *index;

	INIT:

		SV *result=newSV(IF_NAMESIZE);
		char *p=SvPVX(result);
		char *ret;
	
	PPCODE:
		if(SvOK(index)){
			ret=if_indextoname(SvUV(index), p);
			if(ret == p){
				
				SvPOK_on(result);
				SvCUR_set(result, strlen(p));
				mXPUSHs(result);
				XSRETURN(1);
			}
			else {
				XSRETURN_UNDEF;
			}
		}
		else {
			XSRETURN_UNDEF;
		}

void
if_nameindex()

	INIT:

		UV count=0;
		struct if_nameindex *results, *next;
	PPCODE:

		results=if_nameindex();
		
		if(results ==NULL){

			XSRETURN_UNDEF;
		}
		else {
			next=results;
			while((next->if_index !=0 )&&
			(next->if_name != NULL)){
				EXTEND(SP,2);
				mPUSHs(newSVuv(next->if_index));
				mPUSHs(newSVpv(next->if_name, 0));
				count++;
				next=results+count;
			}
			if_freenameindex(results);
			XSRETURN(count);
		}

SV*
getaddrinfo(hostname, servicename, hints, results)
    SV *hostname
    SV *servicename
    SV *hints
    AV *results

  PROTOTYPE: $$$\@

  INIT:
    int ret;
    char *hname=NULL;
    char *sname=NULL;
    struct addrinfo *res;
    struct addrinfo h;
    struct addrinfo *next;
    int len;
    

  PPCODE: 

    h.ai_flags=0;
    h.ai_family=0;
    h.ai_socktype=0;
    h.ai_protocol=0;
    h.ai_addrlen=0;
    h.ai_addr=NULL;
    h.ai_canonname=NULL;
    h.ai_next=NULL;

    // First check that output array is doable
    
    //expectiong a hostname 

    if(SvOK(hostname) && SvPOK(hostname)){
      len=SvCUR(hostname);
      hname=SvPVX(hostname);//SvGROW(hostname,1);
      hname[len]='\0';
      //Perl_croak(aTHX_ "This croaked because: %" SVf "\n", SVfARG(hostname));
    }
    else{
    }
    if(SvOK(servicename) && SvPOK(servicename)){
      len=SvCUR(servicename);
      sname=SvPVX(servicename);//SvGROW(servicename,1);
      sname[len]='\0';
    }

    if(SvOK(hints) && SvROK(hints)){
      SV** temp;
      HV* hv=(HV *)SvRV(hints);

      temp=hv_fetch(hv,"flags",5,1);
      if((temp != NULL ) &&SvIOK(*temp)){

        h.ai_flags = SvIV(*temp);
      }
      temp=hv_fetch(hv,"family",6,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_family = SvIV(*temp);
      }
      temp=hv_fetch(hv,"type",4,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_socktype = SvIV(*temp);
      }
      temp=hv_fetch(hv,"protocol",8,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_protocol = SvIV(*temp);
      }
    }

    //XSRETURN_UNDEF;

    ret=getaddrinfo(hname, sname, &h,&res);



    if(ret!=0){
      // The return array to error?

      SV * e=get_sv("!",GV_ADD);
      sv_setiv(e, ret);
      sv_setpv(e, gai_strerror(ret));
      XSRETURN_UNDEF;
    }
    else{
      // Copy results into output array
      HV *h;
      int count=0;
      next=res;
      while(next){
        count++;
        next=next->ai_next;
      }
      av_extend(results,count);
      //Resize output array to  fit count 
      int i=0;
      next=res;
      while(next){
        h=newHV();
        hv_store(h, "family", 6, newSViv(next->ai_family), 0);
        hv_store(h, "type", 4, newSViv(next->ai_socktype), 0);
        hv_store(h, "protocol", 8, newSViv(next->ai_protocol), 0);
        hv_store(h, "addr", 4, newSVpv((char *)(next->ai_addr), next->ai_addrlen), 0);
        hv_store(h, "canonname", 9, newSVpv(next->ai_canonname,0), 0);

        //Push results to return stack
        next=next->ai_next;
        av_store(results,i,newRV((SV *)h));
        i++;
        //mXPUSHs(newRV((SV *)h));
        //count++;

      }
      freeaddrinfo(res);





      XSRETURN_IV(1);
    }

const char *
gai_strerror(code)
  int code;

SV*
getnameinfo(address, IN_OUT hostname, IN_OUT servicename, flags)
    SV *address
    SV *hostname
    SV *servicename
    SV *flags

  PROTOTYPE: $$$$
  
  INIT:
    int ret;
    char *host;
    char *service;
    int fl;
    int addrlen;
    struct sockaddr *addr;

  PPCODE:

    //Ensure outputs are not readonly
    
    if(SvREADONLY(hostname) || SvREADONLY(servicename)){
            Perl_croak(aTHX_ "%s", PL_no_modify);
    }

    if(SvOK(address) && SvPOK(address)){
      addrlen=SvCUR(address);
      addr=(struct sockaddr *)SvPVX(address);//SvGROW(address,0);
    }

    if(!SvOK(hostname)){
      hostname=sv_2mortal(newSV(NI_MAXHOST+1));

    }

    SvPOK_on(hostname);
    host=SvGROW(hostname, NI_MAXHOST+1);

    if(!SvOK(servicename)){
      servicename=sv_2mortal(newSV(NI_MAXSERV+1));
    }

    SvPOK_on(servicename);
    service=SvGROW(servicename, NI_MAXSERV+1);


    if(SvOK(flags)  && SvIOK(flags)){
      fl=SvIV(flags); 
    }
    else {
      fl=0;
    }
    
    ret=getnameinfo(addr, addrlen, host, NI_MAXHOST, service, NI_MAXSERV, fl);

    if(ret==0){
      //Update the actual length used
      SvCUR_set(hostname, strlen(host));
      SvCUR_set(servicename, strlen(service));

      //Return as no error (true)
      XSRETURN_IV(1);

    }
    else {
      //return as error, and set errno
      SV * e=get_sv("!",GV_ADD);
      sv_setiv(e, ret);
      sv_setpv(e, gai_strerror(ret));
      XSRETURN_UNDEF; 
    }
