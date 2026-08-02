/**
 * Whether a user actually shows as "online" to other users is the AND of two
 * independent facts: do they have a live socket connection right now (see
 * lib/socket.ts's connected-user tracking), and have they opted in to being
 * visible at all (Profile.showOnlineStatus, toggled from Settings). Kept as
 * a pure function so both halves can be tested without a real socket server.
 */
export function computeIsOnline(showOnlineStatus: boolean, connected: boolean): boolean {
  return showOnlineStatus && connected
}
