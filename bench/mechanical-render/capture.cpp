#include <QGuiApplication>
#include <QQuickView>
#include <QQuickItem>
#include <QQmlEngine>
#include <QTimer>
#include <QDir>
int main(int argc,char **argv) {
 QGuiApplication app(argc,argv); QQuickView view;
 view.engine()->addImportPath(QString(argv[1])+"/imports");
 view.setSource(QUrl::fromLocalFile(QString(argv[1])+"/capture.qml"));
 if(view.status()!=QQuickView::Ready)return 2;
 view.resize(1536,1152); view.show(); int n=-1;
 QTimer timer; timer.setInterval(150);
 QObject::connect(&timer,&QTimer::timeout,[&] {
   if(n>=0) {
     QMetaObject::invokeMethod(view.rootObject(),"freezeWaves");
     auto img=view.grabWindow();
     if(!img.save(QString(argv[2])+QString("/%1.png").arg(n)))app.exit(3);
   }
   if(++n==16){app.quit();return;}
   view.rootObject()->setProperty("captureCase",n);
 });
 QDir().mkpath(argv[2]); timer.start(); return app.exec();
}
