<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\DutyController;
use App\Http\Controllers\ManifestController;

Route::get('/health', [DutyController::class, 'health']);
Route::post('/duty/calculate', [DutyController::class, 'calculate']);
Route::get('/manifest/{manifestRef}', [ManifestController::class, 'lookup']);

// Failure injection, so the console can break this service without a
// shell. Writing the file is all php-fail.sh ever did; the two
// controllers already read it on every request.
//
// A backend that can be broken on demand is a demo affordance, not a
// production one - whereIn keeps it to the three known modes rather
// than letting any string through to the filesystem.
Route::put('/failmode/{mode}', function (string $mode) {
    file_put_contents('/opt/app/storage/failmode', $mode);
    return ['failMode' => $mode];
})->whereIn('mode', ['on', 'hang', 'off']);
