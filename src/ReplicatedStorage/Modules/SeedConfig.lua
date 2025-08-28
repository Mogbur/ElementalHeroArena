-- 1 basic berry (cash) + 3 elemental berries (cash + essence)
return {
	Blueberry = {
		id="Blueberry", display="Blueberry Pot",
		element=nil, growSeconds=25, yieldCash=6,
		potColor=Color3.fromRGB(168,100,70),
		stemColor=Color3.fromRGB(60,150,90),
		fruitColorGrowing=Color3.fromRGB(120,160,220),
		fruitColorRipe=Color3.fromRGB(70,120,220),
		potSize=Vector3.new(1.4,0.6,1.4), stemHeight=0.9, fruitSize=0.55,
	},
	Emberberry = {
		id="Emberberry", display="Emberberry Pot",
		element="Fire", yieldEssence={Fire=3}, yieldCash=4, growSeconds=40,
		potColor=Color3.fromRGB(180,80,50),
		stemColor=Color3.fromRGB(70,150,80),
		fruitColorGrowing=Color3.fromRGB(200,120,80),
		fruitColorRipe=Color3.fromRGB(255,80,60),
		potSize=Vector3.new(1.4,0.6,1.4), stemHeight=1.0, fruitSize=0.6,
	},
	Tideberry = {
		id="Tideberry", display="Tideberry Pot",
		element="Water", yieldEssence={Water=3}, yieldCash=4, growSeconds=45,
		potColor=Color3.fromRGB(95,125,165),
		stemColor=Color3.fromRGB(60,150,110),
		fruitColorGrowing=Color3.fromRGB(120,160,220),
		fruitColorRipe=Color3.fromRGB(70,120,220),
		potSize=Vector3.new(1.4,0.6,1.4), stemHeight=1.0, fruitSize=0.6,
	},
	Terraberry = {
		id="Terraberry", display="Terraberry Pot",
		element="Earth", yieldEssence={Earth=3}, yieldCash=5, growSeconds=55,
		potColor=Color3.fromRGB(125,90,60),
		stemColor=Color3.fromRGB(80,140,80),
		fruitColorGrowing=Color3.fromRGB(170,150,100),
		fruitColorRipe=Color3.fromRGB(140,100,70),
		potSize=Vector3.new(1.6,0.7,1.6), stemHeight=1.2, fruitSize=0.7,
	},
}
