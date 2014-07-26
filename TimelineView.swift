//
//  TimelineView.swift
//  Evan Dekhayser
//
//  Created by Evan Dekhayser on 7/25/14.
//  Copyright (c) 2014 Evan Dekhayser. All rights reserved.
//

import UIKit

public struct TimeFrame{
    let date: String
	let text: String
	let image: UIImage?
}

class TimelineView: UIView {
	
	var timeFrames: [TimeFrame]
	
	init(coder aDecoder: NSCoder!) {
		timeFrames = []
		super.init(coder: aDecoder)
	}

	init(width: CGFloat, timeFrames: [TimeFrame]){
		self.timeFrames = timeFrames
		super.init(frame: CGRect.zeroRect)
		
		var i = 0
		var y: CGFloat = 24
		for element in timeFrames{
			let circle = UIView(frame: CGRect(x:10, y:y, width:14, height:14))
			circle.backgroundColor = UIColor.whiteColor()
			circle.layer.borderWidth = 1
			circle.layer.borderColor = UIColor.lightGrayColor().CGColor
			circle.clipsToBounds = true
			circle.layer.cornerRadius = circle.frame.size.width / 2
			addSubview(circle)
			
			if let image = element.image{
				let button = UIButton.buttonWithType(UIButtonType.Custom) as UIButton
				button.frame = CGRect(x: 41, y: y, width: width - 20 - 41, height: 130)
				button.layer.cornerRadius = 10
                button.backgroundColor = UIColor.blackColor()
				button.contentMode = UIViewContentMode.ScaleAspectFit
				button.imageView.contentMode = UIViewContentMode.ScaleAspectFit
				button.clipsToBounds = true
				button.tag = i
				
				button.addTarget(self, action: "tapImage:", forControlEvents: UIControlEvents.TouchUpInside)
				button.setImage(image, forState: UIControlState.Normal)
				button.setImage(image, forState: UIControlState.Selected)
				button.setImage(image, forState: UIControlState.Highlighted)
				button.setImage(image, forState: UIControlState.Disabled)
                
				addSubview(button)
				y += 145
			}
			
			let titleLabel = UILabel(frame: CGRect(x: 41, y: y-5, width: width - 37, height: 18))
			titleLabel.font = UIFont(name: "OpenSans-Semibold", size: 16)
			titleLabel.textColor = UIColor(red: 0/255, green: 183/255, blue: 158/255, alpha: 1)
			titleLabel.text = element.date
			titleLabel.numberOfLines = 0
			titleLabel.sizeToFit()
			addSubview(titleLabel)
			
			let textLabel = UILabel(frame: CGRect(x: 41, y: y+18, width: width - 37, height: 18))
			textLabel.font = UIFont(name: "OpenSans", size: 12)
			textLabel.text = element.text
			textLabel.textColor = UIColor(red: 111/255, green: 111/255, blue: 111/255, alpha: 1)
			textLabel.numberOfLines = 0
			textLabel.sizeToFit()
			addSubview(textLabel)
			
			y += textLabel.frame.size.height + 48.0;
			i++;
		}
		
		let extraSpace: CGFloat = 200
		
		let line = UIView(frame: CGRect(x: 16.5, y: 24, width: 1, height: y + extraSpace))
		line.backgroundColor = UIColor.lightGrayColor()
		addSubview(line)
		sendSubviewToBack(line)
		self.frame = CGRect(x: 0, y: 0, width: width, height: line.frame.height - extraSpace)
	}
    
    func tapImage(button: UIButton){
        
    }
	
}
