import Foundation
import Testing

@testable import Scramble

@Suite("TripAttributes")
struct TripAttributesTests {

  @Test("empty selected returns empty array for every attribute")
  func emptySelected() {
    let attrs = TripAttributes()
    for attribute in TripAttribute.allCases {
      #expect(attrs.selected(attribute).isEmpty)
    }
  }

  @Test("setSingle assigns a single value")
  func setSingleAssigns() {
    var attrs = TripAttributes()
    attrs.setSingle(.duration, value: "weekend")
    #expect(attrs.selected(.duration) == ["weekend"])
  }

  @Test("setSingle replaces previous value")
  func setSingleReplaces() {
    var attrs = TripAttributes()
    attrs.setSingle(.transport, value: "car")
    attrs.setSingle(.transport, value: "plane")
    #expect(attrs.selected(.transport) == ["plane"])
  }

  @Test("setSingle nil clears the attribute")
  func setSingleNilClears() {
    var attrs = TripAttributes()
    attrs.setSingle(.scope, value: "domestic")
    attrs.setSingle(.scope, value: nil)
    #expect(attrs.selected(.scope).isEmpty)
  }

  @Test("toggle adds value when absent")
  func toggleAdds() {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "rain")
    #expect(attrs.selected(.weather) == ["rain"])
  }

  @Test("toggle removes value when present")
  func toggleRemoves() {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "rain")
    attrs.toggle(.weather, value: "rain")
    #expect(attrs.selected(.weather).isEmpty)
  }

  @Test("toggle accumulates multiple values (multi-select weather)")
  func toggleAccumulates() {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "rain")
    attrs.toggle(.weather, value: "cold")
    attrs.toggle(.weather, value: "snow")
    let selected = Set(attrs.selected(.weather))
    #expect(selected == Set(["rain", "cold", "snow"]))
  }

  @Test("toggle removes only matching value, leaves others")
  func toggleRemovesOneLeavesOthers() {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "rain")
    attrs.toggle(.weather, value: "cold")
    attrs.toggle(.weather, value: "rain")
    #expect(attrs.selected(.weather) == ["cold"])
  }

  @Test("round-trip: empty")
  func roundTripEmpty() throws {
    let original = TripAttributes()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TripAttributes.self, from: data)
    #expect(decoded == original)
  }

  @Test("round-trip: single-select values")
  func roundTripSingleSelect() throws {
    var original = TripAttributes()
    original.setSingle(.duration, value: "weekend")
    original.setSingle(.transport, value: "plane")
    original.setSingle(.scope, value: "international")
    original.setSingle(.purpose, value: "leisure")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TripAttributes.self, from: data)
    #expect(decoded == original)
  }

  @Test("round-trip: multi-select weather")
  func roundTripMultiSelectWeather() throws {
    var original = TripAttributes()
    original.toggle(.weather, value: "rain")
    original.toggle(.weather, value: "cold")
    original.toggle(.weather, value: "snow")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TripAttributes.self, from: data)
    #expect(Set(decoded.selected(.weather)) == Set(original.selected(.weather)))
  }

  @Test(
    "round-trip property: decode(encode(x)) == x",
    arguments: TripAttributesTests.generatedSamples()
  )
  func roundTripProperty(sample: TripAttributes) throws {
    let data = try JSONEncoder().encode(sample)
    let decoded = try JSONDecoder().decode(TripAttributes.self, from: data)
    #expect(decoded == sample)
  }

  @Test("decode-failure fallback: corrupt blob → JSONDecoder throws; .init() is empty")
  func decodeFailureFallback() {
    let corrupt = Data([0x00, 0xFF, 0x42])
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(TripAttributes.self, from: corrupt)
    }
    let fallback = TripAttributes()
    for attribute in TripAttribute.allCases {
      #expect(fallback.selected(attribute).isEmpty)
    }
  }

  // MARK: - Sample generator

  static func generatedSamples() -> [TripAttributes] {
    let durations = [nil, "weekend", "week", "two-weeks"]
    let transports: [String?] = [nil, "car", "plane"]
    let scopes: [String?] = [nil, "domestic", "international"]
    let purposes: [String?] = [nil, "leisure", "business"]
    let weatherValues = ["sunny", "rain", "cold", "snow"]

    var samples: [TripAttributes] = []
    for duration in durations {
      for transport in transports {
        for scope in scopes {
          for purpose in purposes {
            for weatherCount in 0...4 {
              var attrs = TripAttributes()
              if let duration { attrs.setSingle(.duration, value: duration) }
              if let transport { attrs.setSingle(.transport, value: transport) }
              if let scope { attrs.setSingle(.scope, value: scope) }
              if let purpose { attrs.setSingle(.purpose, value: purpose) }
              for value in weatherValues.prefix(weatherCount) {
                attrs.toggle(.weather, value: value)
              }
              samples.append(attrs)
            }
          }
        }
      }
    }
    return samples
  }
}
