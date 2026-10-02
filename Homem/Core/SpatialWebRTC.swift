// The iOS binary has no visionOS slice. Keep transport and rendering shared
// while using LiveKit's standalone WebRTC build on Apple Vision Pro.
#if os(visionOS)
import LiveKitWebRTC

typealias RTCCVPixelBuffer = LKRTCCVPixelBuffer
typealias RTCVideoFrame = LKRTCVideoFrame
typealias RTCVideoRenderer = LKRTCVideoRenderer
typealias RTCVideoTrack = LKRTCVideoTrack
typealias RTCConfiguration = LKRTCConfiguration
typealias RTCDataBuffer = LKRTCDataBuffer
typealias RTCDataChannel = LKRTCDataChannel
typealias RTCDataChannelConfiguration = LKRTCDataChannelConfiguration
typealias RTCDefaultVideoDecoderFactory = LKRTCDefaultVideoDecoderFactory
typealias RTCDefaultVideoEncoderFactory = LKRTCDefaultVideoEncoderFactory
typealias RTCIceCandidate = LKRTCIceCandidate
typealias RTCIceConnectionState = LKRTCIceConnectionState
typealias RTCIceGatheringState = LKRTCIceGatheringState
typealias RTCMediaConstraints = LKRTCMediaConstraints
typealias RTCMediaStream = LKRTCMediaStream
typealias RTCPeerConnection = LKRTCPeerConnection
typealias RTCPeerConnectionDelegate = LKRTCPeerConnectionDelegate
typealias RTCPeerConnectionFactory = LKRTCPeerConnectionFactory
typealias RTCRtpReceiver = LKRTCRtpReceiver
typealias RTCRtpTransceiverInit = LKRTCRtpTransceiverInit
typealias RTCSessionDescription = LKRTCSessionDescription
typealias RTCSignalingState = LKRTCSignalingState
func RTCInitializeSSL() { _ = LKRTCInitializeSSL() }
#endif
