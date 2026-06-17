// ================================================================
// LOGISTICS MANAGEMENT SYSTEM (Single File Demo)
// Rust 1.80+
// ================================================================

use std::collections::HashMap;
use std::fmt;

// ================================================================
// MODELS
// ================================================================

#[derive(Debug, Clone)]
pub struct Customer {
    pub customer_id: String,
    pub name: String,
    pub email: String,
    pub active: bool,
}

#[derive(Debug, Clone)]
pub struct Driver {
    pub driver_id: String,
    pub first_name: String,
    pub last_name: String,
    pub license_number: String,
    pub active: bool,
}

#[derive(Debug, Clone)]
pub struct Truck {
    pub truck_id: String,
    pub unit_number: u32,
    pub make: String,
    pub model_year: u16,
    pub mileage: u64,
    pub active: bool,
}

#[derive(Debug, Clone)]
pub struct Trailer {
    pub trailer_id: String,
    pub trailer_number: String,
    pub capacity_lbs: f64,
}

#[derive(Debug, Clone)]
pub struct Route {
    pub route_id: String,
    pub origin: String,
    pub destination: String,
    pub miles: f64,
}

#[derive(Debug, Clone)]
pub struct Load {
    pub load_id: String,
    pub customer_id: String,
    pub weight_lbs: f64,
    pub revenue: f64,
    pub status: LoadStatus,
}

#[derive(Debug, Clone)]
pub struct Trip {
    pub trip_id: String,
    pub load_id: String,
    pub driver_id: String,
    pub truck_id: String,
    pub route_id: String,
    pub fuel_cost: f64,
    pub completed: bool,
}

#[derive(Debug, Clone)]
pub struct MaintenanceRecord {
    pub maintenance_id: String,
    pub truck_id: String,
    pub description: String,
    pub cost: f64,
}

#[derive(Debug, Clone)]
pub struct FuelPurchase {
    pub purchase_id: String,
    pub truck_id: String,
    pub gallons: f64,
    pub amount: f64,
}

#[derive(Debug, Clone)]
pub enum LoadStatus {
    Pending,
    Assigned,
    InTransit,
    Delivered,
    Cancelled,
}

impl fmt::Display for LoadStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LoadStatus::Pending => write!(f, "Pending"),
            LoadStatus::Assigned => write!(f, "Assigned"),
            LoadStatus::InTransit => write!(f, "In Transit"),
            LoadStatus::Delivered => write!(f, "Delivered"),
            LoadStatus::Cancelled => write!(f, "Cancelled"),
        }
    }
}

// ================================================================
// DATABASE
// ================================================================

pub struct LogisticsDB {
    customers: HashMap<String, Customer>,
    drivers: HashMap<String, Driver>,
    trucks: HashMap<String, Truck>,
    trailers: HashMap<String, Trailer>,
    routes: HashMap<String, Route>,
    loads: HashMap<String, Load>,
    trips: HashMap<String, Trip>,
    maintenance: HashMap<String, MaintenanceRecord>,
    fuel_purchases: HashMap<String, FuelPurchase>,
}

impl LogisticsDB {
    pub fn new() -> Self {
        Self {
            customers: HashMap::new(),
            drivers: HashMap::new(),
            trucks: HashMap::new(),
            trailers: HashMap::new(),
            routes: HashMap::new(),
            loads: HashMap::new(),
            trips: HashMap::new(),
            maintenance: HashMap::new(),
            fuel_purchases: HashMap::new(),
        }
    }

    // ============================================================
    // CUSTOMER
    // ============================================================

    pub fn add_customer(&mut self, customer: Customer) {
        self.customers
            .insert(customer.customer_id.clone(), customer);
    }

    pub fn get_customer(&self, id: &str) -> Option<&Customer> {
        self.customers.get(id)
    }

    // ============================================================
    // DRIVER
    // ============================================================

    pub fn add_driver(&mut self, driver: Driver) {
        self.drivers.insert(driver.driver_id.clone(), driver);
    }

    pub fn get_driver(&self, id: &str) -> Option<&Driver> {
        self.drivers.get(id)
    }

    // ============================================================
    // TRUCK
    // ============================================================

    pub fn add_truck(&mut self, truck: Truck) {
        self.trucks.insert(truck.truck_id.clone(), truck);
    }

    pub fn get_truck(&self, id: &str) -> Option<&Truck> {
        self.trucks.get(id)
    }

    // ============================================================
    // TRAILER
    // ============================================================

    pub fn add_trailer(&mut self, trailer: Trailer) {
        self.trailers
            .insert(trailer.trailer_id.clone(), trailer);
    }

    // ============================================================
    // ROUTE
    // ============================================================

    pub fn add_route(&mut self, route: Route) {
        self.routes.insert(route.route_id.clone(), route);
    }

    // ============================================================
    // LOAD
    // ============================================================

    pub fn add_load(&mut self, load: Load) {
        self.loads.insert(load.load_id.clone(), load);
    }

    pub fn assign_load(&mut self, load_id: &str) {
        if let Some(load) = self.loads.get_mut(load_id) {
            load.status = LoadStatus::Assigned;
        }
    }

    // ============================================================
    // TRIP
    // ============================================================

    pub fn create_trip(&mut self, trip: Trip) {
        self.trips.insert(trip.trip_id.clone(), trip);
    }

    pub fn complete_trip(&mut self, trip_id: &str) {
        if let Some(trip) = self.trips.get_mut(trip_id) {
            trip.completed = true;
        }
    }

    // ============================================================
    // MAINTENANCE
    // ============================================================

    pub fn add_maintenance(&mut self, record: MaintenanceRecord) {
        self.maintenance
            .insert(record.maintenance_id.clone(), record);
    }

    // ============================================================
    // FUEL
    // ============================================================

    pub fn add_fuel_purchase(&mut self, purchase: FuelPurchase) {
        self.fuel_purchases
            .insert(purchase.purchase_id.clone(), purchase);
    }

    // ============================================================
    // ANALYTICS
    // ============================================================

    pub fn total_revenue(&self) -> f64 {
        self.loads.values().map(|l| l.revenue).sum()
    }

    pub fn total_weight_moved(&self) -> f64 {
        self.loads.values().map(|l| l.weight_lbs).sum()
    }

    pub fn total_fuel_cost(&self) -> f64 {
        self.fuel_purchases.values().map(|p| p.amount).sum()
    }

    pub fn total_maintenance_cost(&self) -> f64 {
        self.maintenance.values().map(|m| m.cost).sum()
    }

    pub fn delivered_loads(&self) -> usize {
        self.loads
            .values()
            .filter(|l| matches!(l.status, LoadStatus::Delivered))
            .count()
    }

    pub fn active_drivers(&self) -> usize {
        self.drivers.values().filter(|d| d.active).count()
    }

    pub fn active_trucks(&self) -> usize {
        self.trucks.values().filter(|t| t.active).count()
    }

    pub fn print_dashboard(&self) {
        println!();
        println!("================ DASHBOARD ================");
        println!("Customers           : {}", self.customers.len());
        println!("Drivers             : {}", self.drivers.len());
        println!("Trucks              : {}", self.trucks.len());
        println!("Routes              : {}", self.routes.len());
        println!("Loads               : {}", self.loads.len());
        println!("Trips               : {}", self.trips.len());

        println!("------------------------------------------");
        println!("Revenue             : ${:.2}", self.total_revenue());
        println!("Weight Moved        : {:.2} lbs", self.total_weight_moved());
        println!("Fuel Cost           : ${:.2}", self.total_fuel_cost());
        println!(
            "Maintenance Cost    : ${:.2}",
            self.total_maintenance_cost()
        );
        println!("Delivered Loads     : {}", self.delivered_loads());
        println!("Active Drivers      : {}", self.active_drivers());
        println!("Active Trucks       : {}", self.active_trucks());
        println!("==========================================");
    }
}

// ================================================================
// SERVICES
// ================================================================

pub struct DispatchService;

impl DispatchService {
    pub fn dispatch_load(
        db: &mut LogisticsDB,
        load_id: &str,
        driver_id: &str,
        truck_id: &str,
        route_id: &str,
    ) {
        db.assign_load(load_id);

        let trip = Trip {
            trip_id: format!("TRIP-{}", load_id),
            load_id: load_id.to_string(),
            driver_id: driver_id.to_string(),
            truck_id: truck_id.to_string(),
            route_id: route_id.to_string(),
            fuel_cost: 0.0,
            completed: false,
        };

        db.create_trip(trip);
    }
}

// ================================================================
// MAIN
// ================================================================

fn main() {
    let mut db = LogisticsDB::new();

    db.add_customer(Customer {
        customer_id: "CUST001".into(),
        name: "Amazon".into(),
        email: "amazon@example.com".into(),
        active: true,
    });

    db.add_driver(Driver {
        driver_id: "DRV001".into(),
        first_name: "John".into(),
        last_name: "Smith".into(),
        license_number: "DL123456".into(),
        active: true,
    });

    db.add_truck(Truck {
        truck_id: "TRK001".into(),
        unit_number: 1001,
        make: "Volvo".into(),
        model_year: 2024,
        mileage: 45000,
        active: true,
    });

    db.add_route(Route {
        route_id: "R001".into(),
        origin: "Dallas".into(),
        destination: "Houston".into(),
        miles: 240.0,
    });

    db.add_load(Load {
        load_id: "LOAD001".into(),
        customer_id: "CUST001".into(),
        weight_lbs: 42000.0,
        revenue: 6500.0,
        status: LoadStatus::Pending,
    });

    DispatchService::dispatch_load(
        &mut db,
        "LOAD001",
        "DRV001",
        "TRK001",
        "R001",
    );

    db.add_fuel_purchase(FuelPurchase {
        purchase_id: "F001".into(),
        truck_id: "TRK001".into(),
        gallons: 120.0,
        amount: 540.0,
    });

    db.add_maintenance(MaintenanceRecord {
        maintenance_id: "M001".into(),
        truck_id: "TRK001".into(),
        description: "Oil Change".into(),
        cost: 250.0,
    });

    db.print_dashboard();
}