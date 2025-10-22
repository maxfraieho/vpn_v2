// Блокування WebRTC для запобігання витоку IP
const config = {
  iceServers: [{urls: 'stun:stun.l.google.com:19302'}],
  iceCandidatePoolSize: 0
};

// Override RTCPeerConnection
window.RTCPeerConnection = new Proxy(window.RTCPeerConnection, {
  construct(target, args) {
    console.log('WebRTC blocked');
    return new target(config);
  }
});
