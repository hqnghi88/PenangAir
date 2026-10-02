/***
* Name: staticvars
* Author: minhduc0711
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model staticvars

global {	
	file roof_texture <- file('../images/building_texture/roof_top.jpg') ;		
	list textures <- [file('../images/building_texture/texture1.jpg'),file('../images/building_texture/texture2.jpg'),file('../images/building_texture/texture3.jpg'),file('../images/building_texture/texture4.jpg'),file('../images/building_texture/texture5.jpg'),
	file('../images/building_texture/texture6.jpg'),file('../images/building_texture/texture7.jpg'),file('../images/building_texture/texture8.jpg'),file('../images/building_texture/texture9.jpg'),file('../images/building_texture/texture10.jpg')];

	int simType<-0;
	float sizeCoeff <-10.0;
	
	string map_center <- "48.8566140,2.3522219";
	// Simulation parameters
	int max_cars<-1000;
	int max_motorbikes<-500;
	int max_bus<-500;
	// Simulation parameters
	int n_cars;
	int n_motorbikes;
	int n_bus;
	int road_scenario;
	int display_mode<-1;
	// Save params' old values to detect value changes
	int n_cars_prev;
	int n_motorbikes_prev;
	int n_bus_prev;
	int road_scenario_prev;
	int display_mode_prev;
	
	// Parameter of visualization to avoid z fighting
	float Z_LVL1 <- 0.1;
	float Z_LVL2 <- 0.2;
	float Z_LVL3 <- 0.3;
	
	
	// Pollution diffusion
	float pollutant_decay_rate <-  0.99; //0.99;
	float pollutant_diffusion <- 0.05;
	int grid_size <- 50;
	int grid_depth <- 10; // cubic meters
	
	graph road_network;
	
	// Buildings
	float min_height <- 0.1;
	float mean_height <- 1.3;
	string type_outArea <- "outArea";	
	
	// Daytime management
	string starting_date_string <- "00 00 00";
	float refreshing_rate_plot <- 1#mn;
	
	// Daytime color blender
	bool day_time_color_blender <- false;
	map<date,rgb> day_time_colors <- [
		date("00 00 00", "HH mm ss")::#midnightblue,
		date("06 00 00","HH mm ss")::#deepskyblue,
		date("14 00 00","HH mm ss")::#gold,
		date("18 00 00","HH mm ss")::#darkorange,
		date("19 00 00","HH mm ss")::#blue
	];
	float day_time_color_blend_factor <- 0.2;
	
	// Daytime traffic demand
	int max_number_of_cars <- 500 const:true;
	int max_number_of_motorbikes <- 1000 const:true;
	bool day_time_traffic <- false;
	map<date,float> daytime_trafic_peak <- [
		date("01 00 00", "HH mm ss")::0.1,
		date("04 00 00", "HH mm ss")::0.1,
		date("07 00 00", "HH mm ss")::1.0,
		date("08 00 00", "HH mm ss")::1.0,
		date("09 00 00", "HH mm ss")::0.6,
		date("10 00 00", "HH mm ss")::0.5,
		date("11 30 00", "HH mm ss")::1.0,
		date("13 00 00", "HH mm ss")::0.8,
		date("16 00 00", "HH mm ss")::0.4,
		date("17 00 00", "HH mm ss")::1.0,
		date("18 00 00", "HH mm ss")::1.0,
		date("19 00 00", "HH mm ss")::0.85,
		date("20 00 00", "HH mm ss")::0.75,
		date("22 30 00", "HH mm ss")::0.6,
		date("23 30 00", "HH mm ss")::0.5
	];


	// Pollution threshold 
	string THRESHOLD_HAZARDOUS <- " Hazardous";
	string THRESHOLD_VERY_UNHEALTY <- " Very Unhealthy";
	string THRESHOLD_UNHEALTHY <- " Unhealty";
	string THRESHOLD_UNHEALTHY_SENSITIVE <- " Unhealthy for \nSensitive Groups";
	string THRESHOLD_MODERATE <- " Moderate";
	string THRESHOLD_GOOD <- " Good";
		map<rgb, string> pollutions <- [#green::THRESHOLD_GOOD, #yellow::THRESHOLD_MODERATE, #red::THRESHOLD_UNHEALTHY, rgb(66,18,39,255)::THRESHOLD_HAZARDOUS];
	
	map<string,rgb> zone_colors <- [
		THRESHOLD_GOOD:: #green, //rgb(104,225,66,255), 
		THRESHOLD_MODERATE:: #yellow, //rgb(255,255,83,255), 
		THRESHOLD_UNHEALTHY_SENSITIVE::#orange,//rgb(240,131,51,255),
		THRESHOLD_UNHEALTHY::#red, //rgb(218,56,50,255), 
		THRESHOLD_VERY_UNHEALTY::rgb(116,49,121,255),
		THRESHOLD_HAZARDOUS::rgb(66,18,39,255)
	];
	map<rgb,int> zone_colors1 <- [
//		 #green-100::0,  
		 #green::0,  
		 #yellow::5,   
		#orange::10, 
		#red::15, 
		rgb(116,49,121,255)::20,
		rgb(66,18,39,255)::30
	];
	map<rgb,float> zone_colors2 <- [
		 #grey::0,  
		 #yellow::0.1,   
		#orange::0.2, 
		#red::0.5, 
		rgb(116,49,121,255)::0.7,
		rgb(66,18,39,255)::0.9
	];
	map<int,string> thresholds_pollution <- [
		0::THRESHOLD_GOOD,
		51::THRESHOLD_MODERATE,
		101::THRESHOLD_UNHEALTHY_SENSITIVE,
		151::THRESHOLD_UNHEALTHY,
		201::THRESHOLD_VERY_UNHEALTY,
		301::THRESHOLD_HAZARDOUS
	];

	
	// Color 
	string BUILDING_BASE <- "building_base";
	string BUILDING_OUTAREA <- "building_outArea";
	string DECO_BUILDING <- "deoc_building";
	string NATURAL <- "naturals";
	string DUMMY_ROAD <- "dummy_road";
	string CAR <- "car";
	string MOTOBYKE <- "motobyke";
	string CLOSED_ROAD_TRAFFIC <- "closed_road_traffic";
	string CLOSED_ROAD_POLLUTION <- "closed_road_pollution";
	string NOT_CONGESTED_ROAD <- "not congested roads";
	string CONGESTED_ROAD <- " congested_roads";
	string ROAD_POLLUTION_DISPLAY <- "road pollution";
	string TEXT_COLOR <- "Text color";
	string AQI_CHART <- "AQI Charts";
	string lb_Time<-"Date Time";
	string lb_Traffic_Incident<-"Real-time Traffic Incident";
	string lb_AQI_update<-"Real-time AQI";
	string lb_cars<-"% Electrical Cars";
	string lb_motobike<-"% Electrical Motorbikes";
	string lb_bus<-"% Electrical Bus";
	string lb_rates_EG<-"Total Rate of Electrical vs Gas";

	map<string,rgb> palet <- [
		BUILDING_BASE::#white,
		BUILDING_OUTAREA::rgb(60,60,60),
		DECO_BUILDING::rgb(60,60,60),
		NATURAL::rgb (165, 199, 238,255),
		DUMMY_ROAD::#grey,
		CAR:: #orange,
		MOTOBYKE:: #cyan,
		CLOSED_ROAD_TRAFFIC:: #darkblue,		
		CLOSED_ROAD_POLLUTION:: #white,
		NOT_CONGESTED_ROAD:: #white,
		CONGESTED_ROAD::#red,
		ROAD_POLLUTION_DISPLAY:: #white,
		TEXT_COLOR::#white,
		AQI_CHART::#white
	];

	float decrease_coeff <- 0.99;
	int size <- 300;
	field instant_heatmap <- field(size, size);

	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);
	map<string, geometry> legends_geom1 <- ["Electrical Vehicle"::square(800),  "Gas Vehicle"::circle(400),  "Roads"::circle(400)]; 
	map<string, geometry> legends_geom2 <- ["Electrical Vehicle"::square(160),  "Gas Vehicle"::circle(80),  "Roads"::circle(80)]; 
	map<string, geometry> legends_geom4 <- ["Electrical Vehicle"::square(80),  "Gas Vehicle"::circle(40),  "Roads"::circle(40)]; 
	map<rgb, string> legends <- [#cyan::"Electrical Vehicle", #blue::"Gas Vehicle", rgb(#white)::"Roads"];
	font text <- font("Arial", 18, #bold);
	font title <- font("Arial", 24, #bold);
	int get_pollution_threshold(float aqi) {
		int threshold <- 0;
		loop thr over: thresholds_pollution.keys {
			if(aqi > thr) {
				threshold <- thr;
			}
		}
		return threshold;
	}
	
	string get_pollution_state(float aqi) {
		return thresholds_pollution[get_pollution_threshold(aqi)];
	}
	
	rgb get_pollution_color(float aqi) {
		return zone_colors[thresholds_pollution[get_pollution_threshold(aqi)]];		
	}
} 

