import CoreMedia

enum WindowLifecycleState {
    case hidden
    case visible
    case grace(lastSeen: CMTime)
}
