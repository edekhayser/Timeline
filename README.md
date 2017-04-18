Timeline
========

Timeline like the Path iOS app

<p align="center"><img title="Open and close animation" src="https://github.com/edekhayser/Timeline/blob/master/Screenshot.png"/></p>

## Usage ##

The timeline is a UIView subclass, and can be taller than the screen. It is best used within a scrollview.

To initialize the timeline, use this code:

```swift
let timeline = TimelineView(bulletType: .Diamond, timeFrames: [/*timeFrames*/])
```

The bullet type can be changed to any of the following types:

```swift
public enum BulletType{
	case Circle
	case Hexagon
	case Diamond
	case DiamondSlash
	case Carrot
	case Arrow
}
```

The time frames must all be instances of the TimeFrame stuct. An array of TimeFrames may look like this:

```swift
let frames = [
	TimeFrame(text: "New Year's Day", date: "January 1", image: UIImage(named: "fireworks.jpeg")),
	TimeFrame(text: "That's right. No image is necessary!", date: "No image?", image: nil),
	TimeFrame(text: "Hope this helps someone!", date: "That's it!", image: nil)
]
```
			
After the timeline is initialized, it is ready to go. For more customization, you can edit the following properties:

```swift
public var timeFrames: [TimeFrame]
  
public var lineColor: UIColor = UIColor.lightGrayColor()
	
public var titleLabelColor: UIColor = UIColor(red: 0/255, green: 180/255, blue: 160/255, alpha: 1)

public var detailLabelColor: UIColor = UIColor(red: 110/255, green: 110/255, blue: 110/255, alpha: 1)

public var bulletType: BulletType = BulletType.Diamond

public var showBulletOnRight: Bool = false
```

For more precise detail on what these properties do, look at the inline documentation.

At this point, the timeline is completely ready to use. Add it to a scroll view, add constraints, and you are ready to go!

See the sample project for an example of how to do integrate this view into your project.

## Conclusion ##

That's about all there is to it! Hope you find it useful, and let me know if you use it in any production apps. It's great to see my work used by others.
