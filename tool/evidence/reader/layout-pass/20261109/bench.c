#include <string.h>
#include <tesseract/capi.h>
#include <leptonica/allheaders.h>
#include <stdio.h>
#include <time.h>
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e3+t.tv_nsec/1e6;}
int main(int c,char**v){
  PIX*pix=pixRead(v[2]); if(!pix){fprintf(stderr,"no image\n");return 1;}
  TessBaseAPI*api=TessBaseAPICreate();
  if(TessBaseAPIInit2(api,v[1],"eng",OEM_LSTM_ONLY)){fprintf(stderr,"init\n");return 1;}
  TessBaseAPISetPageSegMode(api,PSM_AUTO);
  for(int round=0;round<3;round++){
    TessBaseAPISetImage2(api,pix);
    double a=now(); TessPageIterator*it=TessBaseAPIAnalyseLayout(api); double b=now();
    int words=0,lines=0,blocks=0,pars=0; int x1,y1,x2,y2; float slope=0;
    if(it){ do{ if(TessPageIteratorIsAtBeginningOf(it,RIL_BLOCK))blocks++; if(TessPageIteratorIsAtBeginningOf(it,RIL_PARA))pars++; if(TessPageIteratorIsAtBeginningOf(it,RIL_TEXTLINE)){lines++; if(lines==3&&TessPageIteratorBaseline(it,RIL_TEXTLINE,&x1,&y1,&x2,&y2)&&x2!=x1) slope=(float)(y2-y1)/(x2-x1);} words++; }while(TessPageIteratorNext(it,RIL_WORD)); TessPageIteratorDelete(it);}
    double c0=now(); TessBaseAPISetImage2(api,pix); double c1=now(); TessBaseAPIRecognize(api,NULL); double d=now();
    char*h=TessBaseAPIGetHOCRText(api,0); int hw=0; for(char*p=h;(p=strstr(p,"ocrx_word"));p++)hw++; TessDeleteText(h);
    double e=now(); TessBaseAPISetImage2(api,pix); TessPageIterator*it2=TessBaseAPIAnalyseLayout(api); TessPageIteratorDelete(it2); double f=now(); TessBaseAPIRecognize(api,NULL); double g=now();
    printf("round %d: layout %.0f ms (blocks %d pars %d lines %d words %d, line-3 slope %.4f) | full recognize %.0f ms (hOCR words %d) | recognize after layout on same image %.0f ms\n",round,b-a,blocks,pars,lines,words,slope,d-c1,hw,g-f);
    TessBaseAPIClear(api);
  }
  TessBaseAPIEnd(api); TessBaseAPIDelete(api); pixDestroy(&pix); return 0;}
