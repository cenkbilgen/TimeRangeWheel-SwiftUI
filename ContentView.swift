//
//  ContentView.swift
//  TimeRangePicker
//
//  Created by Cenk Bilgen on 2020-05-29.
//  Copyright © 2020 Cenk Bilgen. All rights reserved.
//

import SwiftUI
import Combine

struct ContentView: View {
  var body: some View {
    Clock()
      .environmentObject(Clock.Model(startHour: 1, durationHours: 3.5))
      .padding()
  }
}

struct Clock: View {
  @Environment(\.locale) var locale: Locale
 
  private var orientationChangedPublisher = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)

  @State private var frame: CGRect = .zero

  
  // MARK: Model
  
  class Model: ObservableObject {
    @Published var start: Angle
    @Published var end:  Angle
    let hoursInClock: Int = 12 // TODO
    
    init(startHour: Double, durationHours: TimeInterval) {
      self.start = Angle.degrees(360/Double(hoursInClock)*startHour).normalized
      self.end = Angle.degrees(360/Double(hoursInClock)*(startHour + Double(durationHours))).normalized
    }
    
    var startHour: TimeInterval { start.normalized.degrees/TimeInterval(360/hoursInClock) }
    var endHour: TimeInterval { end.normalized.degrees/TimeInterval(360/hoursInClock) }
    
    var interval: TimeInterval { (endHour - startHour)*60*60 }
    var hours: Int { Int(interval/60/60) }
    var minutes: Int { Int((interval - TimeInterval(hours*60*60))/60) }
  }
  
  @EnvironmentObject var model: Model
  var start: Angle { model.start }
  var end: Angle { model.end}
  
  enum DraggingDial { case start, end }
  @GestureState var dragging: (dial: DraggingDial?, startAngle: Angle?)?
  
  var durationString: String {
    let components: DateComponents = DateComponents(hour: model.hours, minute: model.minutes)
    return DateComponentsFormatter.localizedString(from: components, unitsStyle: .brief) ?? "-"
  }
    
  var body: some View {
    let drag = DragGesture(minimumDistance: 0, coordinateSpace: CoordinateSpace.named("circle"))
      .updating($dragging) { (value, dragging, transaction) in
        let touchDistance: CGFloat = 10
        let t = value.translation
        let l = value.location
        let sl = value.startLocation
        let distance = sqrt(pow(t.height, 2) + pow(t.width, 2))
        let y = (distance < touchDistance ? sl.y : l.y)-self.frame.height/2
        let x = (distance < touchDistance ? sl.x : l.x)-self.frame.width/2
        let a: Angle = y.isZero ? .zero : y.isLess(than: 0) ? Angle.radians(Double(atan(-x/y))).normalized :
          Angle.radians(Double(atan(-x/y)) + .pi).normalized
        //print("l: \(l) | a: \(a)")
        if dragging == nil {
          dragging = (nil, a)
        }
        if a < self.model.start {
          dragging?.dial = .start
        } else if a <  self.model.end {
          if self.model.end-a < a-self.model.start {
            dragging?.dial = .end
          } else {
            dragging?.dial = .start
          }
        } else {
          dragging?.dial = .end
        }
        if let dial = dragging?.dial {
          if dial == .start { // && self.model.end != a {
            DispatchQueue.main.async { self.model.start = a }
          } else if dial == .end { //} && self.model.start != a {
            DispatchQueue.main.async { self.model.end = a }
          }
        }
    }
    
    return Circle().fill()
      .aspectRatio(contentMode: .fit)
      .overlay(Wedge(start: start, end: end).fill(Color.blue))
      .overlay(Dial(angle: start)
        .stroke(lineWidth: dragging?.dial == .start ? 16 : 8)
        .fill(Color(.systemGreen)))
      .overlay(Dial(angle: end)
        .stroke(lineWidth: dragging?.dial == .end ? 16 : 8)
        .fill(Color(.systemRed)))
      .overlay(HourMarkers(hours: [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], inRect: frame))
      //.overlay(Arrow(start: start, end: end - .degrees(10), unitRadius: 0.67))
      .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
      .overlay(Circle().inset(by: frame.width/2*0.20).fill())
      .overlay(VStack {
          Text("\(Int(start.degrees))° -> \(Int(end.degrees))°")
          Text("\(durationString)")
        }
        .font(.system(.largeTitle, design: .monospaced)).foregroundColor(.white))
      .coordinateSpace(name: "circle")
      .gesture(drag)
      .overlay(GeometryReader { geometry in
        Color.clear.onReceive(self.orientationChangedPublisher) { _ in
          let frame = geometry.frame(in: CoordinateSpace.named("circle"))
          print("Frame \(frame)")
          self.frame = frame
        }
      })
  }
  
  struct HourMarkers: View {
    @EnvironmentObject var model: Model
    let hours: [Int]
    let inRect: CGRect

    private func angle(hour: Int) -> Angle {
      Angle.degrees(360/Double(model.hoursInClock)*Double(hour % model.hoursInClock))
    }
    
    var body: some View {
      let angles = hours.map {
        Angle.degrees(360/Double(model.hoursInClock)*Double($0 % model.hoursInClock))
      }
      return ZStack {
        ForEach(hours.indices, id: \.self) { i in
          return Image(systemName: "\(self.hours[i]).circle.fill")
            .renderingMode(.template)
            .foregroundColor(Color.white.opacity(angles[i] <= self.model.start || angles[i] >= self.model.end ? 0 : 1))
            .padding()
            .rotationEffect(-angles[i])
            .offset(x: 0, y: -self.inRect.height/2 + 20)
            .rotationEffect(angles[i])
            .imageScale(.large)
        }
      }
    }
  }
}

struct Wedge: Shape {
  let start, end: Angle
  
  func path(in rect: CGRect) -> Path {
    let center = rect.center
    return Path { (path) in
      path.move(to: center)
      let endNormalized = end >= start ? end  : end + Angle(degrees: 360)
      print("\(Int(start.degrees)) -> \(Int(endNormalized.degrees))")
      path.addArc(center: center, radius: rect.width/2, startAngle: start + .degrees(-90), endAngle: endNormalized + .degrees(-90), clockwise: false, transform: .identity)
      path.move(to: center)
    }
  }
}

struct Arc: Shape {
  let start, end: Angle
  let unitRadius: CGFloat
  
  func path(in rect: CGRect) -> Path {
    let center = rect.center
    let r = unitRadius*rect.width/2
    return Path { (path) in
      path.move(to: center)
      path.move(to: CGPoint(x: center.x, y: r))
      path.addArc(center: center, radius: unitRadius*rect.width/2, startAngle: .zero, endAngle: start + end, clockwise: true)
      let rotation = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(start.radians)).translatedBy(x: -center.x, y: -center.y)
      path = path.applying(rotation)
    }
  }
}

// TODO
struct Arrow: View {
  let start, end: Angle
  let unitRadius: CGFloat
  
  var body: some View {
    EmptyView()
  }
}

struct Dial: Shape {
  let angle: Angle
  
  func path(in rect: CGRect) -> Path {
    let center = rect.center
    return Path { (path) in
      path.move(to: center)
      path.addLine(to: CGPoint(x: center.x, y: 0))
      let rotation = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(angle.radians)).translatedBy(x: -center.x, y: -center.y)
      path = path.applying(rotation)
    }
  }
}
  
extension CGRect {
  var center: CGPoint {
    CGPoint(x: minX+width/2, y: minY+height/2)
  }
}

extension Angle {
  var normalized: Angle {
    self.degrees.isLess(than: 0) ?
      .degrees((360 + self.degrees.remainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)) :
      .degrees(self.degrees.truncatingRemainder(dividingBy: 360))
  } // returns 0 to 359
}

extension Angle: CustomDebugStringConvertible {
  public var debugDescription: String { "\(Int(self.degrees))" }
}

