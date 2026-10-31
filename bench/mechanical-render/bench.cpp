#include <QGuiApplication>
#include <QQuickView>
#include <QQuickItem>
#include <QQmlEngine>
#include <QTimer>
#include <QElapsedTimer>
#include <QMutex>
#include <QMutexLocker>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QSet>
#include <QRegularExpression>
#include <QSGRendererInterface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <sys/resource.h>
#include <time.h>
#include <algorithm>
#include <vector>
#include <cstdio>
static double cpu() { timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return t.tv_sec+t.tv_nsec/1e9; }
static double mainCpu() { timespec t; clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t); return t.tv_sec+t.tv_nsec/1e9; }
static double gpuNs() {
 QDir dir("/proc/self/fdinfo"); QSet<QString> seen; double sum=0; bool found=false;
 for(const auto &name:dir.entryList(QDir::Files)) {
  QFile file(dir.filePath(name)); if(!file.open(QIODevice::ReadOnly)) continue;
  QString data=QString::fromUtf8(file.readAll());
  auto id=QRegularExpression("drm-client-id:\\s*(\\d+)").match(data);
  if(!id.hasMatch() || seen.contains(id.captured(1))) continue;
  seen.insert(id.captured(1));
  auto busy=QRegularExpression("drm-engine-render:\\s*(\\d+)\\s+ns").match(data);
  if(busy.hasMatch()) {sum+=busy.captured(1).toDouble();found=true;}
 }
 return found?sum:-1;
}
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv);
 QQuickView view;
 view.engine()->addImportPath(QString::fromLocal8Bit(argv[1])+"/imports");
 view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])+"/bench.qml"));
 if (view.status()!=QQuickView::Ready) return 2;
 view.setResizeMode(QQuickView::SizeRootObjectToView); view.resize(1280,360); view.show();
 auto root=view.rootObject();
 QObject::connect(&view,&QQuickWindow::sceneGraphInitialized,&view,[&] {
  auto ctx=QOpenGLContext::currentContext();
  if(ctx) fprintf(stderr,"GL renderer: %s\n",ctx->functions()->glGetString(GL_RENDERER));
 },Qt::DirectConnection);
 if(argc>2) {
  root->setProperty("motion",true); root->setProperty("pattern",true);
  QTimer::singleShot(2500,[&] {root->setProperty("held",35);
  QTimer::singleShot(200,[&] {QVariant state; QMetaObject::invokeMethod(root,"debugState",Q_RETURN_ARG(QVariant,state)); fprintf(stderr,"STATE %s\n",qPrintable(state.toString()));
   for(auto o:root->findChildren<QObject*>()) {
    if(o->property("amount").isValid() && (o->property("pressed").toBool() || o->property("amount").toDouble()>0)) fprintf(stderr,"GLOW active=%d pressed=%d amount=%f base=%s press=%s color=%s\n",o->property("active").toBool(),o->property("pressed").toBool(),o->property("amount").toDouble(),qPrintable(o->property("baseColor").value<QColor>().name()),qPrintable(o->property("pressColor").value<QColor>().name()),qPrintable(o->property("color").value<QColor>().name()));
   }
   view.grabWindow().save(QString::fromLocal8Bit(argv[2]));app.quit();});});
  return app.exec();
 }

 struct Phase { const char *name; bool ripple; int rate; };
 std::vector<Phase> phases={{"static_6",false,6},{"ripple_6",true,6},{"idle",false,0}};
 QElapsedTimer clock; clock.start();
 QMutex mutex; std::vector<double> gaps; bool collecting=false; double last=-1;
 QObject::connect(&view,&QQuickWindow::frameSwapped,&view,[&] {
  QMutexLocker guard(&mutex); double now=clock.nsecsElapsed()/1e6;
  if (collecting && last>=0) gaps.push_back(now-last);
  last=now;
 },Qt::DirectConnection);
 int at=-1, pressStart=0; double cpuStart=0,timeStart=0,mainStart=0,gpuStart=-1;
 QTimer warmup,measure; warmup.setSingleShot(true); measure.setSingleShot(true);
 std::function<void()> next=[&] {
  at++; if (at>=int(phases.size())) {app.quit();return;}
  root->setProperty("rate",0); root->setProperty("sequence",0);
  root->setProperty("motion",phases[at].ripple); root->setProperty("rate",phases[at].rate);
  warmup.start(2000);
 };
 QObject::connect(&warmup,&QTimer::timeout,[&] {
  {QMutexLocker guard(&mutex); gaps.clear(); last=-1; collecting=true;}
  gpuStart=gpuNs(); mainStart=mainCpu(); cpuStart=cpu(); timeStart=clock.nsecsElapsed()/1e9;
  pressStart=root->property("presses").toInt(); measure.start(8000);
 });
 QObject::connect(&measure,&QTimer::timeout,[&] {
  double seconds=clock.nsecsElapsed()/1e9-timeStart,used=cpu()-cpuStart,mainUsed=mainCpu()-mainStart,gpuEnd=gpuNs();
  std::vector<double> copy; {QMutexLocker guard(&mutex);collecting=false;copy=gaps;}
  std::sort(copy.begin(),copy.end());
  auto percentile=[&](double fraction) { return copy.empty()?0:copy[std::min(copy.size()-1,size_t(fraction*(copy.size()-1)))];};
  rusage usage; getrusage(RUSAGE_SELF,&usage);
  QVariant running; QMetaObject::invokeMethod(root,"runningCount",Q_RETURN_ARG(QVariant,running));
  QJsonObject o{{"phase",phases[at].name},{"wall_s",seconds},{"cpu_s",used},{"cpu_one_core_pct",100*used/seconds},{"main_thread_cpu_pct",100*mainUsed/seconds},{"gpu_render_busy_pct",gpuStart<0 || gpuEnd<0 ? -1 : (gpuEnd-gpuStart)/1e9/seconds*100},{"frames",int(copy.size())+(copy.empty()?0:1)},{"p50_frame_gap_ms",percentile(.5)},{"p95_frame_gap_ms",percentile(.95)},{"max_frame_gap_ms",copy.empty()?0:copy.back()},{"peak_rss_kb",double(usage.ru_maxrss)},{"presses",root->property("presses").toInt()-pressStart},{"active_key_animations",running.toInt()},{"graphics_api",int(view.rendererInterface()->graphicsApi())}};
  auto line=QJsonDocument(o).toJson(QJsonDocument::Compact); fprintf(stdout,"%s\n",line.constData());fflush(stdout);
  next();
 });
 QTimer::singleShot(1000,next);
 return app.exec();
}
