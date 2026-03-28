const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────
// 1. チャットメッセージ着信時にプッシュ通知を送信
//    Triggered when a new chat message is created
// ─────────────────────────────────────────────
exports.sendNewMessageNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const { chatId } = context.params;

    if (!message || !message.senderId) return null;

    // チャット情報を取得
    const chatDoc = await db.collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return null;
    const chat = chatDoc.data();

    // メンバー全員に通知（送信者以外）
    const members = chat.members || [];
    const recipients = members.filter((uid) => uid !== message.senderId);
    if (recipients.length === 0) return null;

    // 送信者の表示名を取得
    const senderDoc = await db.collection("users").doc(message.senderId).get();
    const senderName = senderDoc.exists
      ? senderDoc.data().displayName || "Someone"
      : "Someone";

    // 受信者のFCMトークンを取得
    const tokenPromises = recipients.map((uid) =>
      db.collection("users").doc(uid).get()
    );
    const userDocs = await Promise.all(tokenPromises);

    const tokens = [];
    userDocs.forEach((doc) => {
      if (doc.exists && doc.data().fcmToken) {
        tokens.push(doc.data().fcmToken);
      }
    });

    if (tokens.length === 0) return null;

    const payload = {
      notification: {
        title: senderName,
        body: message.text || "📷 Image",
      },
      data: {
        type: "chat",
        chatId,
        senderId: message.senderId,
      },
    };

    return messaging.sendEachForMulticast({ tokens, ...payload });
  });

// ─────────────────────────────────────────────
// 2. アプリ内通知をプッシュ通知として送信
//    Send in-app notification as push notification
// ─────────────────────────────────────────────
exports.sendAppNotification = functions.firestore
  .document("notifications/{userId}/items/{notifId}")
  .onCreate(async (snap, context) => {
    const notif = snap.data();
    const { userId } = context.params;

    if (!notif) return null;

    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) return null;

    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return null;

    const payload = {
      token: fcmToken,
      notification: {
        title: notif.title || "(DIS)CONNECT",
        body: notif.body || "",
      },
      data: {
        type: notif.type || "general",
        targetId: notif.targetId || "",
      },
    };

    return messaging.send(payload).catch((err) => {
      console.error("sendAppNotification error:", err);
    });
  });

// ─────────────────────────────────────────────
// 3. 毎日ランダムな時刻にデトックススケジュールを配信
//    Daily random detox schedule broadcast via FCM topic
//    Runs every day at 07:00 JST (22:00 UTC)
// ─────────────────────────────────────────────
exports.updateDailySchedule = functions.pubsub
  .schedule("0 22 * * *")
  .timeZone("Asia/Tokyo")
  .onRun(async (_context) => {
    // ランダムな開始時刻を生成（12:30〜19:00 JST の間）
    const totalOffsetMin = Math.floor(Math.random() * 391); // 0〜390分（=6時間30分）
    const baseMin = 12 * 60 + 30; // 12:30
    const absMin = baseMin + totalOffsetMin;
    const startHour = Math.floor(absMin / 60);
    const startMin = absMin % 60 < 30 ? 0 : 30;
    const durationOptions = [30, 60, 90, 120]; // 分
    const duration =
      durationOptions[Math.floor(Math.random() * durationOptions.length)];

    const scheduleData = {
      startHour,
      startMin,
      duration,
      date: new Date().toISOString().slice(0, 10),
    };

    // Firestoreにスケジュールを保存
    await db
      .collection("config")
      .doc("dailySchedule")
      .set(scheduleData, { merge: true });

    // FCMトピック "daily_schedule" に通知
    const message = {
      topic: "daily_schedule",
      notification: {
        title: "今日のデトックス時間が決まりました",
        body: `${startHour}:${String(startMin).padStart(2, "0")} から ${duration}分間`,
      },
      data: {
        type: "daily_schedule",
        startHour: String(startHour),
        startMin: String(startMin),
        duration: String(duration),
      },
    };

    return messaging.send(message).catch((err) => {
      console.error("updateDailySchedule FCM error:", err);
    });
  });

// ─────────────────────────────────────────────
// 4. 毎日 00:00 JST にストリークをリセット
//    Daily streak reset cron at midnight JST
// ─────────────────────────────────────────────
exports.resetDailyStreaks = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("Asia/Tokyo")
  .onRun(async (_context) => {
    const today = new Date().toISOString().slice(0, 10);

    // 全ユーザーのstreakLastDateを確認し、昨日以前なら連続日数を0にリセット
    const usersSnap = await db.collection("users").get();
    const batch = db.batch();
    let resetCount = 0;

    usersSnap.forEach((doc) => {
      const data = doc.data();
      const lastDate = data.streakLastDate || "";

      // 昨日の日付を計算
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const yestStr = yesterday.toISOString().slice(0, 10);

      // 最後のデトックス日が昨日でも今日でもない場合はリセット
      if (lastDate !== today && lastDate !== yestStr) {
        batch.update(doc.ref, { streak: 0 });
        resetCount++;
      }
    });

    await batch.commit();
    console.log(`resetDailyStreaks: reset ${resetCount} users on ${today}`);
    return null;
  });
