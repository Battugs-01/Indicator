# MT5 on AWS EC2 — Deploy Guide

## 1. AWS EC2 Instance үүсгэх

### AWS Console дээр:
1. https://console.aws.amazon.com → EC2 → Launch Instance
2. Тохиргоо:

| Тохиргоо | Утга |
|----------|------|
| Name | `MT5-Trading-Bot` |
| AMI | **Microsoft Windows Server 2022 Base** |
| Instance type | **t3.medium** (2 vCPU, 4GB RAM) — EA 1-2 бол хангалттай |
| Key pair | Шинэ key pair үүсгэ (`.pem` файл татагдана — ХАДГАЛ!) |
| Storage | **30 GB gp3** (SSD) |
| Security Group | Доорх портууд нээ |

### Security Group (Firewall):

| Port | Protocol | Source | Зориулалт |
|------|----------|--------|-----------|
| 3389 | TCP | My IP | Remote Desktop (RDP) |

> **Анхааруулга:** 3389 портыг "My IP" гэж тавь, "0.0.0.0/0" бүү тавь!

### Үнэ (ойролцоо):
- **t3.medium**: ~$30/сар (on-demand)
- **t3.small** (2 vCPU, 2GB): ~$15/сар (хамгийн бага, 1 EA-д хангалттай)
- Windows лиценз: AMI-д багтсан
- **Reserved Instance** (1 жил): ~40% хямд

---

## 2. EC2 руу холбогдох (Remote Desktop)

### Windows Password авах:
1. EC2 Console → Instances → instance сонго
2. **Actions → Security → Get Windows Password**
3. `.pem` key файлаа upload хий
4. Password гарна — **хадгал!**

### macOS-с холбогдох:
1. **Microsoft Remote Desktop** татаж суулга (App Store-с үнэгүй)
2. Шинэ PC нэм:
   - PC name: `EC2-ийн Public IP` (EC2 console-с хар)
   - User: `Administrator`
   - Password: дээр авсан password

### Холбогдох:
```
PC: 54.123.45.67  (чиний EC2 public IP)
User: Administrator
Password: ****
```

---

## 3. MT5 суулгах (EC2 дотор)

EC2-н Windows дотор:

### 3.1 Browser нээх
- Server Manager → Local Server → **IE Enhanced Security → Off** болго
- Edge/Chrome нээ

### 3.2 MT5 татах
- Брокерийн сайтаас MT5 татах
- Эсвэл: https://www.metatrader5.com/en/download

### 3.3 Суулгах
```
1. mt5setup.exe ажиллуул
2. Суулгах хавтас: C:\Program Files\MetaTrader 5\
3. Дуусахад MT5 нээгдэнэ
4. Брокерийн серверээ сонго
5. Login + Password оруул
6. Account-д нэвтэр
```

### 3.4 EA файл хуулах
```
EA файлын байршил:
C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\[ID]\MQL5\Experts\

Хуулах арга:
- Remote Desktop дээр copy-paste (файл drag&drop)
- Эсвэл OneDrive/Google Drive-с татах
```

---

## 4. MT5 тохируулах

### 4.1 Automated Trading идэвхжүүлэх
```
MT5 → Tools → Options → Expert Advisors tab:
  ✅ Allow automated trading
  ✅ Allow DLL imports (хэрэгтэй бол)
```

### 4.2 EA chart дээр нэмэх
```
1. Navigator → Expert Advisors → чиний EA
2. Chart дээр чирж тавь (XAU/USD, 15min)
3. EA properties → Inputs → SL, TP, lot size тохируул
4. Common tab → ✅ Allow live trading
5. OK дар
```

### 4.3 Chart-н баруун дээд буланд "сайхан царай" 😊 icon байвал EA ажиллаж байна

---

## 5. 24/7 ажиллуулах тохиргоо

### 5.1 Windows auto-login (restart хийгдвэл автомат нэвтрэх)
```
Win+R → netplwiz
→ "Users must enter a user name and password" checkbox-г БОЛИУЛ
→ Administrator password оруул
→ OK
```

### 5.2 MT5 startup дээр нэмэх
```
Win+R → shell:startup
→ MT5-ийн shortcut-г энэ хавтас руу хуул
```

### 5.3 Screen saver унтраах
```
Settings → Personalization → Lock Screen → Screen saver → None
Settings → System → Power → Screen: Never
Settings → System → Power → Sleep: Never
```

### 5.4 Windows Update автомат restart болиулах
```
Settings → Windows Update → Advanced options
→ Active hours: 00:00 - 23:59
```

---

## 6. Хянах (Monitoring)

### 6.1 MT5 Mobile App
- iOS/Android дээр MT5 суулгаад ижил account-р нэвтэр
- Нээлттэй позиц, баланс, түүх харагдана

### 6.2 AWS CloudWatch
```
EC2 Console → Monitoring tab:
- CPU utilization (< 50% байх ёстой)
- Network (трафик хэвийн эсэх)
```

### 6.3 Alarm тохируулах
```
CloudWatch → Alarms → Create Alarm:
- Metric: StatusCheckFailed
- Action: SNS → Email notification
→ EC2 унтарвал email ирнэ
```

---

## 7. Хамгаалалт (Security)

### 7.1 Security Group шалгах
- Зөвхөн **чиний IP**-с RDP нээ
- Шаардлагагүй порт бүү нээ

### 7.2 Strong password
- Administrator password хүчтэй байх (12+ тэмдэгт)

### 7.3 Backup
```
EC2 → Actions → Image and templates → Create Image
→ AMI snapshot үүсгэ (сар бүр)
```

### 7.4 Elastic IP (тогтмол IP)
```
EC2 → Elastic IPs → Allocate → Associate
→ EC2 instance-тэй холбо
→ Restart хийгдсэн ч IP өөрчлөгдөхгүй
```

---

## 8. Зардал хэмнэх

### Reserved Instance (1 жил):
```
t3.medium: ~$18/сар (on-demand $30 → 40% хэмнэнэ)
t3.small:  ~$10/сар
```

### Spot Instance (хямд, гэхдээ унтарч болно — trading-д ЗӨВ БИШ!):
- Бүү хэрэглэ! Spot instance дундаас нь унтарч болно

### Зөвлөмж:
- **t3.small** ($15/сар) эхлээд хангалттай
- Ажиллаж байгааг баталгаажуулсны дараа **Reserved** ав

---

## Түргэн шалгах жагсаалт

```
☐ EC2 instance ажиллаж байна
☐ RDP-р холбогдож чадаж байна
☐ MT5 суулгасан, account-д нэвтэрсэн
☐ EA файл хуулсан, chart дээр нэмсэн
☐ Automated trading идэвхжүүлсэн
☐ EA "сайхан царай" icon харагдаж байна
☐ Auto-login тохируулсан
☐ MT5 startup дээр нэмсэн
☐ Sleep/Screen saver унтраасан
☐ Elastic IP холбосон
☐ CloudWatch alarm тохируулсан
☐ MT5 Mobile App-р шалгасан
```

---

## Дараагийн алхам

1. MQL5 bot (.mq5) бичих → compile → .ex5
2. Strategy Tester дээр backtest хийх
3. Demo account дээр 1-2 долоо хоног турших
4. Live account руу шилжих
