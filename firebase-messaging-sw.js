importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBhhdcJ7Yigw5VGxuJxXSicqqHPe2xNcCY",
  authDomain: "tuneout-a7c7b.firebaseapp.com",
  projectId: "tuneout-a7c7b",
  storageBucket: "tuneout-a7c7b.firebasestorage.app",
  messagingSenderId: "798608722916",
  appId: "1:798608722916:web:95d9766c02bdcfd52455f1"
});

const messaging = firebase.messaging();

// バックグラウンドでメッセージを受信したときの処理
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification || {};
  self.registration.showNotification(title || '(DIS)CONNECT', {
    body: body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    data: payload.data || {}
  });
});
