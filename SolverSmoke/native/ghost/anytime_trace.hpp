#pragma once
#include <vector>
#include <mutex>
#include <chrono>
#include <limits>
namespace benchmark_trace {
struct Event {double elapsed,solve,cost;std::vector<int> values;};
inline std::mutex mutex;
inline std::vector<Event> events;
inline double best=std::numeric_limits<double>::infinity();
inline std::chrono::steady_clock::time_point origin,solve_origin;
inline void observe(double cost,const std::vector<int>& values) {
    std::lock_guard<std::mutex> guard(mutex);
    if(cost>=best)return;
    auto stamp=std::chrono::steady_clock::now();best=cost;
    events.push_back({std::chrono::duration<double>(stamp-origin).count(),
        std::chrono::duration<double>(stamp-solve_origin).count(),cost,values});
}
inline void reset() {events.clear();best=std::numeric_limits<double>::infinity();origin=std::chrono::steady_clock::now();solve_origin=origin;}
}
#define BENCHMARK_GHOST_INCUMBENT(cost, values) benchmark_trace::observe(cost, values)
