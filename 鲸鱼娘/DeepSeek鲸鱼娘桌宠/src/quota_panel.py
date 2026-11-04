import os, json, subprocess
from PyQt5.QtCore import Qt, QTimer, QThread, pyqtSignal
from PyQt5.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QScrollArea, QFrame, QProgressBar, QGridLayout, QAction

class Reader(QThread):
    result = pyqtSignal(object, str)
    def run(self):
        try:
            exe = os.path.join(os.environ['LOCALAPPDATA'], 'Programs', 'magpie', 'magpie.exe')
            p = subprocess.run([exe, 'quota', '--json'], capture_output=True,
                               timeout=40, creationflags=0x08000000)
            if p.returncode: raise RuntimeError('Magpie 读取失败')
            self.result.emit(json.loads(p.stdout.decode('utf-8-sig')), '')
        except Exception as e: self.result.emit(None, str(e))

class QuotaPanel(QWidget):
    def __init__(self):
        super().__init__(None, Qt.Tool | Qt.WindowStaysOnTopHint)
        from PyQt5.QtGui import QFontDatabase
        QFontDatabase.addApplicationFont(os.path.join(os.environ.get('WINDIR',r'C:\Windows'),'Fonts','msyh.ttc'))
        self.setWindowTitle('鲸鱼娘 · 多供应商额度')
        self.resize(470, 570)
        self.setMinimumSize(420, 360)
        self.setObjectName('wallet')
        self.setStyleSheet('''
          QWidget {color:#23324c;font:11px "Microsoft YaHei UI";}
          QWidget#wallet {background:#f3f6fc;}
          QLabel {background:transparent;}
          QLabel#heading {font-size:12px;font-weight:700;color:#172b50;}
          QLabel#muted {color:#8692a6;font-size:10px;}
          QLabel#name {font-size:12px;font-weight:600;color:#253957;}
          QLabel#value {font-size:12px;font-weight:700;color:#284b85;}
          QLabel#badge {background:#eaf0ff;color:#5271ad;border-radius:8px;padding:2px 5px;font-size:10px;}
          QFrame#card {background:white;border:1px solid #e7ecf5;border-radius:10px;}
          QScrollArea {background:transparent;border:none;}
          QScrollArea > QWidget > QWidget {background:transparent;}
          QScrollBar:vertical {background:transparent;width:5px;margin:4px 0;}
          QScrollBar::handle:vertical {background:#ccd7e9;border-radius:2px;min-height:30px;}
          QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical {height:0;}
          QScrollBar::add-page:vertical,QScrollBar::sub-page:vertical {background:transparent;}
          QProgressBar {background:#edf2fa;border:none;border-radius:3px;height:5px;max-height:5px;}
          QProgressBar::chunk {background:#72a0f7;border-radius:3px;}
          QPushButton {background:#447be8;color:white;border:none;border-radius:11px;padding:7px;font-weight:600;}
          QPushButton:hover {background:#3469d1;}
          QPushButton:disabled {background:#a9bfeb;}
        ''')
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12,12,12,10); layout.setSpacing(7)
        eyebrow=QLabel('WHALE WALLET  /  鲸鱼娘'); eyebrow.setObjectName('muted')
        heading=QLabel('今天也要额度自由'); heading.setObjectName('heading')
        self.status = QLabel('正在连接本机 Magpie…'); self.status.setObjectName('muted'); self.status.setWordWrap(True)
        self.scroll=QScrollArea(); self.scroll.setWidgetResizable(True)
        container=QWidget(); self.cards=QHBoxLayout(container); self.cards.setContentsMargins(0,0,5,0); self.cards.setSpacing(7); self.columns=[]
        for _ in range(2):
            column=QVBoxLayout(); column.setSpacing(7); column.setContentsMargins(0,0,0,0); column.setAlignment(Qt.AlignTop); self.cards.addLayout(column,1); self.columns.append(column)
        self.scroll.setWidget(container)
        self.button = QPushButton('刷新钱包')
        note=QLabel('本机读取 · 每分钟更新 · 各平台积分独立计算'); note.setObjectName('muted'); note.setAlignment(Qt.AlignCenter)
        for item in (eyebrow,heading,self.status,self.scroll,self.button,note): layout.addWidget(item)
        self.button.clicked.connect(self.refresh)
        self.worker = None
        self.timer = QTimer(self); self.timer.timeout.connect(self.refresh); self.timer.start(60000)
        self.refresh()
    def refresh(self):
        if self.worker and self.worker.isRunning(): return
        self.button.setEnabled(False)
        self.worker = Reader(self); self.worker.result.connect(self.received); self.worker.start()
    def received(self, accounts, error):
        from datetime import datetime
        self.button.setEnabled(True)
        if error:
            self.status.setText('刷新失败，保留旧数据：'+error); return
        for column in self.columns:
            while column.count():
                item=column.takeAt(0)
                if item.widget(): item.widget().deleteLater()
        heights=[0,0]
        count=0
        for a in accounts:
            if a['provider'] in ('codex','deepseek-2'): continue
            count+=1
            card=QFrame(); card.setObjectName('card'); body=QVBoxLayout(card); body.setContentsMargins(10,9,10,10); body.setSpacing(4)
            top=QHBoxLayout(); name=QLabel(a['name']); name.setObjectName('name'); top.addWidget(name); top.addStretch()
            badge=QLabel('API 余额' if a.get('balance') else ('每日积分' if a['provider']=='loomy' else '账户额度')); badge.setObjectName('badge'); badge.hide(); body.addLayout(top)
            if a.get('error'): body.addWidget(QLabel('暂时无法读取 · 请查看官方控制台'))
            if a.get('balance'):
                label=QLabel(a['balance']); label.setObjectName('value'); body.addWidget(label)
            for q in a.get('windows',[]):
                title=QLabel(q['name']); title.setObjectName('muted'); body.addWidget(title)
                if q.get('text'): value=q.get('display','未知').replace('credits','积分')
                elif q.get('limit') and 'remaining' in q:
                    remaining=q['limit']-q['amount'] if 'amount' in q else q['limit']*q['remaining']/100
                    value=f"{remaining:,.2f}".rstrip('0').rstrip('.')+'  剩余'
                else: value=f"{q.get('remaining',0):.2f}%  剩余"
                label=QLabel(value); label.setObjectName('value'); body.addWidget(label)
                if not q.get('text') and 'remaining' in q:
                    bar=QProgressBar(); bar.setRange(0,1000); bar.setValue(round(max(0,min(100,q['remaining']))*10)); bar.setTextVisible(False); body.addWidget(bar)
                    if q.get('limit'):
                        caption=QLabel(f"总额度 {q['limit']:,}"+(' tokens' if q.get('unit')=='tokens' else '')); caption.setObjectName('muted'); body.addWidget(caption)
            index=0 if heights[0]<=heights[1] else 1
            self.columns[index].addWidget(card)
            heights[index]+=card.sizeHint().height()+7
        if not any(a['provider']=='xiaomi' for a in accounts):
            note=QLabel('MiMo 小米额度请前往官方控制台查看'); note.setObjectName('muted'); note.setWordWrap(True); self.columns[0 if heights[0]<=heights[1] else 1].addWidget(note)

        self.status.setText(f'●  已连接 {count} 个来源   ·   '+datetime.now().strftime('%H:%M 更新'))
    def toggle(self):
        if self.isVisible(): self.hide()
        else: self.show(); self.raise_(); self.refresh()

def install(pet, tray):
    panel=QuotaPanel()
    pet._quota_panel=panel
    original=pet._build_menu
    def build():
        original()
        action=QAction('查看供应商实时额度',pet.menu)
        action.triggered.connect(panel.toggle)
        pet.menu.insertAction(pet.menu.actions()[0],action)
    pet._build_menu=build
    action=QAction('查看供应商实时额度',tray.contextMenu())
    action.triggered.connect(panel.toggle)
    tray.contextMenu().insertAction(tray.contextMenu().actions()[0],action)



