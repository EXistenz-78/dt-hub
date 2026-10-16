import Foundation

/// One person as the whole-body model sees them: the 18 OpenPose body joints, the face (68 points) and both hands
/// (21 points each). The points carry their confidence; the drawing applies the threshold. An empty array means the
/// detector gives no face or no hand (Vision gives the body only).
struct DPFigure: Equatable, Sendable {
  var body: DPPerson
  var face: [DPPoint]
  var leftHand: [DPPoint]
  var rightHand: [DPPoint]

  init(body: DPPerson, face: [DPPoint] = [], leftHand: [DPPoint] = [], rightHand: [DPPoint] = []) {
    self.body = body
    self.face = face
    self.leftHand = leftHand
    self.rightHand = rightHand
  }
}
