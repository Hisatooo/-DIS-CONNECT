const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────
// 1. 毎日 07:00 JST にランダムなデトックススケジュールを決定・配信
//    Daily random detox schedule broadcast via FCM topic
//    Runs every day at 07:00 JST
// ─────────────────────────────────────────────
exports.updateDailySchedule = functions.pubsub
    .schedule("0 7 * * *")
    .timeZone("Asia/Tokyo")
    .onRun(async (_context) => {
        // JST の今日の日付を取得
        const jstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
        const todayJST = jstNow.toISOString().slice(0, 10);

        // ランダムな開始時刻を生成（12:00〜19:00 JST の間、15分刻み）
        const startOptions = [];
        for (let h = 12; h <= 18; h++) {
            for (let m = 0; m < 60; m += 15) {
                if (h === 18 && m > 45) continue;
                startOptions.push({hour: h, min: m});
            }
        }
        const picked =
            startOptions[Math.floor(Math.random() * startOptions.length)];
        const startHour = picked.hour;
        const startMin = picked.min;
        const durationOptions = [30, 60, 90, 120]; // 分
        const duration =
            durationOptions[
                Math.floor(Math.random() * durationOptions.length)
            ];

        const scheduleData = {
            startHour,
            startMin,
            duration,
            date: todayJST,
            notified: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        // Firestore に保存
        await db.collection("config").doc("dailySchedule").set(scheduleData);
        await db.collection("groupDetox").doc(todayJST).set(scheduleData);

        // FCMトピック "daily_schedule" に朝7時の告知通知
        const startLabel =
            `${startHour}:${String(startMin).padStart(2, "0")}`;
        const endTotalMin = startHour * 60 + startMin + duration;
        const endLabel =
            `${Math.floor(endTotalMin / 60)}:` +
            `${String(endTotalMin % 60).padStart(2, "0")}`;

        const message = {
            topic: "daily_schedule",
            notification: {
                title: "🎯 今日の一斉デトックス時間、決定！",
                body:
                    `⏰ ${startLabel}〜${endLabel}（${duration}分間）\n` +
                    "今すぐ予約して仲間と一緒にデトックスしよう 👊",
            },
            data: {
                type: "daily_schedule",
                startHour: String(startHour),
                startMin: String(startMin),
                duration: String(duration),
                date: todayJST,
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                        badge: 1,
                    },
                },
            },
        };

        return messaging.send(message).catch((err) => {
            console.error("updateDailySchedule FCM error:", err);
        });
    });

// ─────────────────────────────────────────────
// 2. 毎日 00:00 JST にストリークをリセット
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
                batch.update(doc.ref, {streak: 0});
                resetCount++;
            }
        });

        await batch.commit();
        console.log(`resetDailyStreaks: reset ${resetCount} users on ${today}`);
        return null;
    });

// ─────────────────────────────────────────────
// 3. 5分ごとに一斉デトックス開始チェック
//    Every 5 min: check if group detox is starting now,
//    notify reserved users and trigger app blocking
// ─────────────────────────────────────────────
exports.notifyGroupDetoxStart = functions.pubsub
    .schedule("*/5 * * * *")
    .timeZone("Asia/Tokyo")
    .onRun(async (_context) => {
        const jstNow = new Date(Date.now() + 9 * 60 * 60 * 1000);
        const todayJST = jstNow.toISOString().slice(0, 10);
        const currentMin =
            jstNow.getUTCHours() * 60 + jstNow.getUTCMinutes();

        // 今日のスケジュールを取得
        const scheduleDoc = await db
            .collection("groupDetox")
            .doc(todayJST)
            .get();
        if (!scheduleDoc.exists) {
            console.log("notifyGroupDetoxStart: no schedule for today");
            return null;
        }

        const schedule = scheduleDoc.data();
        if (schedule.notified === true) {
            console.log("notifyGroupDetoxStart: already notified");
            return null;
        }

        const scheduleMin = schedule.startHour * 60 + schedule.startMin;

        // 開始時刻の ±4 分以内なら発火
        if (Math.abs(currentMin - scheduleMin) > 4) {
            return null;
        }

        // 予約済みユーザーのFCMトークンを収集
        const reservationsSnap = await db
            .collection("groupDetox")
            .doc(todayJST)
            .collection("reservations")
            .where("cancelled", "==", false)
            .get();

        if (reservationsSnap.empty) {
            console.log("notifyGroupDetoxStart: no reservations");
            await scheduleDoc.ref.update({notified: true});
            return null;
        }

        // Collect tokens: prefer token on reservation, fall back to users
        const tokenSet = new Set();
        const userFetchPromises = [];

        reservationsSnap.forEach((doc) => {
            const data = doc.data();
            if (data.fcmToken) {
                tokenSet.add(data.fcmToken);
            } else if (doc.id) {
                userFetchPromises.push(
                    db.collection("users").doc(doc.id).get().then(
                        (userDoc) => {
                            if (userDoc.exists && userDoc.data().fcmToken) {
                                tokenSet.add(userDoc.data().fcmToken);
                            }
                        }
                    )
                );
            }
        });

        if (userFetchPromises.length > 0) {
            await Promise.all(userFetchPromises);
        }

        const tokens = Array.from(tokenSet);

        const startLabel =
            `${schedule.startHour}:` +
            `${String(schedule.startMin).padStart(2, "0")}`;
        const endTotalMin =
            schedule.startHour * 60 + schedule.startMin + schedule.duration;
        const endLabel =
            `${Math.floor(endTotalMin / 60)}:` +
            `${String(endTotalMin % 60).padStart(2, "0")}`;

        // 予約ユーザーへ開始通知（アプリブロック起動トリガー含む）
        const chunks = [];
        for (let i = 0; i < tokens.length; i += 500) {
            chunks.push(tokens.slice(i, i + 500));
        }

        for (const chunk of chunks) {
            const multicast = {
                tokens: chunk,
                notification: {
                    title: "🔥 スタート！みんなで一斉デトックス！",
                    body: `${reservationsSnap.size}人が参加中 💪 ${startLabel}〜${endLabel} さあ、乗り越えよう 📵`,
                },
                data: {
                    type: "group_detox_start",
                    startHour: String(schedule.startHour),
                    startMin: String(schedule.startMin),
                    duration: String(schedule.duration),
                    date: todayJST,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            "content-available": 1,
                        },
                    },
                },
            };
            await messaging.sendEachForMulticast(multicast).catch((err) => {
                console.error("notifyGroupDetoxStart multicast error:", err);
            });
        }

        // notified フラグを立てる
        await scheduleDoc.ref.update({
            notified: true,
            notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(
            `notifyGroupDetoxStart: sent to ${tokens.length} users`
        );
        return null;
    });
