//
//  ViewController.swift
//  Timeline
//
//  Created by Evan Dekhayser on 7/26/14.
//  Copyright (c) 2014 Evan Dekhayser. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
	
	var scrollView: UIScrollView!
    var timeline:   TimelineView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		scrollView = UIScrollView(frame: view.bounds)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(scrollView)
		
		view.addConstraints([
			NSLayoutConstraint(item: scrollView, attribute: .left, relatedBy: .equal, toItem: view, attribute: .left, multiplier: 1.0, constant: 0),
			NSLayoutConstraint(item: scrollView, attribute: .top, relatedBy: .equal, toItem: view, attribute: .top, multiplier: 1.0, constant: 29),
			NSLayoutConstraint(item: scrollView, attribute: .right, relatedBy: .equal, toItem: view, attribute: .right, multiplier: 1.0, constant: 0),
			NSLayoutConstraint(item: scrollView, attribute: .bottom, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 1.0, constant: 0)
			])
		
		timeline = TimelineView(bulletType: .circle, timeFrames: [
			TimeFrame(text: "New Year's Day", date: "January 1", image: UIImage(named: "fireworks.jpeg")),
			TimeFrame(text: "The month of love!", date: "February 14", image: UIImage(named: "heart.png")),
			TimeFrame(text: "Comes like a lion, leaves like a lamb", date: "March",  image: nil),
			TimeFrame(text: "Dumb stupid pranks.", date: "April 1", image: UIImage(named: "april.jpeg")),
			TimeFrame(text: "That's right. No image is necessary!", date: "No image?", image: nil),
			TimeFrame(text: "This control can stretch. It doesn't matter how long or short the text is, or how many times you wiggle your nose and make a wish. The control always fits the content, and even extends a while at the end so the scroll view it is put into, even when pulled pretty far down, does not show the end of the scroll view.", date: "Long text", image: nil),
			TimeFrame(text: "Hope this helps someone!", date: "That's it!", image: nil)
			])
		scrollView.addSubview(timeline)
		scrollView.addConstraints([
			NSLayoutConstraint(item: timeline, attribute: .left, relatedBy: .equal, toItem: scrollView, attribute: .left, multiplier: 1.0, constant: 0),
			NSLayoutConstraint(item: timeline, attribute: .bottom, relatedBy: .lessThanOrEqual, toItem: scrollView, attribute: .bottom, multiplier: 1.0, constant: 0),
			NSLayoutConstraint(item: timeline, attribute: .top, relatedBy: .equal, toItem: scrollView, attribute: .top, multiplier: 1.0, constant: 0),
			NSLayoutConstraint(item: timeline, attribute: .right, relatedBy: .equal, toItem: scrollView, attribute: .right, multiplier: 1.0, constant: 0),
			
			NSLayoutConstraint(item: timeline, attribute: .width, relatedBy: .equal, toItem: scrollView, attribute: .width, multiplier: 1.0, constant: 0)
			])

        view.sendSubview(toBack: scrollView)
	}
	
    @IBAction func bulletChanged(_ sender: UISegmentedControl) {
        timeline.bulletType = [BulletType.circle, BulletType.hexagon, BulletType.diamond, BulletType.diamondSlash, BulletType.carrot, BulletType.arrow][sender.selectedSegmentIndex]
    }

	override var prefersStatusBarHidden : Bool {
		return true
	}
	
	
}

